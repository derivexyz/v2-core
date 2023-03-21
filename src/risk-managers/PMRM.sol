// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

import "../interfaces/IManager.sol";
import "../interfaces/IAccounts.sol";
import "../interfaces/IDutchAuction.sol";
import "../interfaces/ICashAsset.sol";
import "../interfaces/IOption.sol";
import "../interfaces/ISecurityModule.sol";
import "../interfaces/ISpotJumpOracle.sol";
import "../interfaces/IPCRM.sol";
import "../interfaces/IFutureFeed.sol";

import "../libraries/OptionEncoding.sol";
import "../libraries/StrikeGrouping.sol";
import "../libraries/Black76.sol";
import "../libraries/SignedDecimalMath.sol";
import "../libraries/DecimalMath.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";
/**
 * @title PortfolioMarginRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract PMRM {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for int;
  using SafeCast for uint;

  struct NewPortfolio {
    /// cash amount or debt
    int cash;
    OtherAsset[] otherAssets;
    /// option holdings per expiry
    ExpiryHoldings[] expiries;
  }

  struct OtherAsset {
    address asset;
    int amount;
  }

  struct ExpiryHoldings {
    uint expiry;
    StrikeHolding[] calls;
    StrikeHolding[] puts;
  }

  struct StrikeHolding {
    /// strike price of held options
    uint strike;
    int amount;
  }

  struct PortfolioExpiryData {
    uint expiry;
    uint callCount;
    uint putCount;
  }

  ///////////////
  // Variables //
  ///////////////

  uint MAX_EXPIRIES = 11;

  uint public constant MAX_STRIKES = 64;

  IAccounts public immutable accounts;
  IOption public immutable option;
  ICashAsset public immutable cashAsset;
  IFutureFeed public immutable futureFeed;
  ISettlementFeed public immutable settlementFeed;
  ISpotJumpOracle public spotJumpOracle;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    IAccounts accounts_,
    IFutureFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    ICashAsset cashAsset_,
    IOption option_,
    ISpotJumpOracle spotJumpOracle_
  ) {
    accounts = accounts_;
    futureFeed = futureFeed_;
    settlementFeed = settlementFeed_;
    cashAsset = cashAsset_;
    option = option_;
    spotJumpOracle = spotJumpOracle_;
  }

  /**
   * @notice Arrange portfolio into cash + arranged
   *         array of [strikes][calls / puts / forwards].
   * @param assets Array of balances for given asset and subId.
   * @return portfolio Cash + option holdings.
   */
  function _arrangePortfolio(IAccounts.AssetBalance[] memory assets)
    internal
    view
    returns (NewPortfolio memory portfolio)
  {
    uint assetLen = assets.length;
    PortfolioExpiryData[] memory expiryCount =
      new PortfolioExpiryData[](MAX_EXPIRIES > assetLen ? assetLen : MAX_EXPIRIES);
    uint seenExpiries = 0;

    for (uint i = 0; i < assetLen; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry,, bool isCall) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
        bool found = false;
        for (uint j = 0; j < seenExpiries; j++) {
          if (expiryCount[j].expiry == optionExpiry) {
            if (isCall) {
              expiryCount[j].callCount++;
            } else {
              expiryCount[j].putCount++;
            }
            found = true;
            break;
          }
        }
        if (!found) {
          expiryCount[seenExpiries++] =
            PortfolioExpiryData({expiry: optionExpiry, callCount: isCall ? 1 : 0, putCount: isCall ? 0 : 1});
        }
      }
    }

    portfolio.expiries = new ExpiryHoldings[](seenExpiries);

    for (uint i = 0; i < seenExpiries; ++i) {
      portfolio.expiries[i] = ExpiryHoldings({
        expiry: expiryCount[i].expiry,
        calls: new StrikeHolding[](expiryCount[i].callCount),
        puts: new StrikeHolding[](expiryCount[i].putCount)
      });
    }

    uint otherAssetCount = 0;
    for (uint i; i < assets.length; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry, uint strike, bool isCall) = OptionEncoding.fromSubId(uint96(currentAsset.subId)); // TODO: safecast

        uint expiryIndex = findInArray(portfolio.expiries, optionExpiry, portfolio.expiries.length);

        ExpiryHoldings memory expiry = portfolio.expiries[expiryIndex];
        if (isCall) {
          expiry.calls[--expiryCount[expiryIndex].callCount] =
            StrikeHolding({strike: strike, amount: currentAsset.balance});
        } else {
          expiry.puts[--expiryCount[expiryIndex].putCount] =
            StrikeHolding({strike: strike, amount: currentAsset.balance});
        }
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
      } else {
        otherAssetCount++;
      }
    }

    for (uint i; i < seenExpiries; ++i) {
      ExpiryHoldings memory expiry = portfolio.expiries[i];
      // TODO: does this sort in place in the greater portfolio?
      if (expiry.calls.length > 1) {
        _quickSortStrikes(expiry.calls, 0, int(expiry.calls.length - 1));
      }
      if (expiry.puts.length > 1) {
        _quickSortStrikes(expiry.puts, 0, int(expiry.puts.length - 1));
      }
    }

    portfolio.otherAssets = new OtherAsset[](otherAssetCount);

    for (uint i; i < assets.length; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) != address(option) && address(currentAsset.asset) != address(cashAsset)) {
        portfolio.otherAssets[--otherAssetCount] =
          OtherAsset({asset: address(currentAsset.asset), amount: currentAsset.balance});
      }
    }

    return portfolio;
  }

  function findInArray(ExpiryHoldings[] memory expiryData, uint expiryToFind, uint arrayLen)
    internal
    pure
    returns (uint index)
  {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (expiryData[i].expiry == expiryToFind) {
          return (i);
        }
      }
      revert("expiry not found");
    }
  }

  function _quickSortStrikes(StrikeHolding[] memory arr, int left, int right) internal pure {
    int i = left;
    int j = right;
    if (i == j) {
      return;
    }
    uint pivot = arr[uint(left + (right - left) / 2)].strike;
    while (i <= j) {
      while (arr[uint(i)].strike < pivot) {
        i++;
      }
      while (pivot < arr[uint(j)].strike) {
        j--;
      }
      if (i <= j) {
        (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
        i++;
        j--;
      }
    }
    if (left < j) {
      _quickSortStrikes(arr, left, j);
    }
    if (i < right) {
      _quickSortStrikes(arr, i, right);
    }
  }

  //////////
  // View //
  //////////

  function arrangePortfolio(IAccounts.AssetBalance[] memory assets)
    external
    view
    returns (NewPortfolio memory portfolio)
  {
    return _arrangePortfolio(assets);
  }

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction();

  error PCRM_InvalidBidPortion();

  error PCRM_MarginRequirementNotMet(int initMargin);

  error PCRM_InvalidMarginParam();
}
