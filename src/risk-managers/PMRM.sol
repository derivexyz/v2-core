// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/IDutchAuction.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/ISecurityModule.sol";
import "src/interfaces/ISpotJumpOracle.sol";
import "src/interfaces/IPCRM.sol";
import "src/interfaces/IFutureFeed.sol";

import "src/libraries/OptionEncoding.sol";
import "src/libraries/StrikeGrouping.sol";
import "src/libraries/Black76.sol";
import "src/libraries/SignedDecimalMath.sol";
import "src/libraries/DecimalMath.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";
// TODO: interface
import "src/feeds/MTMCache.sol";
import "../interfaces/IChainlinkSpotFeed.sol";

/**
 * @title PortfolioMarginRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */

contract PMRM is BaseManager {
  using IntLib for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for int;
  using SafeCast for uint;

  struct NewPortfolio {
    uint spotPrice;
    /// cash amount or debt
    int cash;
    OtherAsset[] otherAssets;
    /// option holdings per expiry
    ExpiryHoldings[] expiries;
    // Calculated values
    int mtm;
    int fwdLosses;
    int shortOptionContingency;
  }

  struct OtherAsset {
    address asset;
    int amount;
  }

  struct ExpiryHoldings {
    uint expiry;
    StrikeHolding[] calls;
    StrikeHolding[] puts;
    uint forwardPrice;
  }

  struct StrikeHolding {
    /// strike price of held options
    uint strike;
    uint vol;
    int amount;
  }

  struct SpreadHolding {
    uint strikeLower;
    uint strikeUpper;
    int amount;
  }

  struct PortfolioExpiryData {
    uint expiry;
    uint callCount;
    uint putCount;
  }

  struct Scenario {
    uint spotShock; // i.e. 1.2e18 = 20% spot shock up
    uint volShock; // i.e. 0.7e18 = 30% vol down
  }

  ///////////////
  // Variables //
  ///////////////

  uint MAX_EXPIRIES = 11;

  uint public constant MAX_STRIKES = 64;

  IChainlinkSpotFeed public immutable spotFeed;
  ISpotJumpOracle public spotJumpOracle;
  MTMCache public mtmCache;

  Scenario[] public scenarios;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    IAccounts accounts_,
    IFutureFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    ICashAsset cashAsset_,
    IOption option_,
    IChainlinkSpotFeed spotFeed_,
    ISpotJumpOracle spotJumpOracle_,
    MTMCache mtmCache_
  ) BaseManager(accounts_, futureFeed_, settlementFeed_, cashAsset_, option_) {
    spotFeed = spotFeed_;
    spotJumpOracle = spotJumpOracle_;
    mtmCache = mtmCache_;
  }

  function setScenarios(Scenario[] memory _scenarios) external {
    for (uint i = 0; i < _scenarios.length; i++) {
      if (scenarios.length <= i) {
        scenarios.push(_scenarios[i]);
      } else {
        scenarios[i] = _scenarios[i];
      }
    }
    for (uint i = _scenarios.length; i < scenarios.length; i++) {
      delete scenarios[i];
    }
  }

  ///////////
  // Hooks //
  ///////////

  /**
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(uint accountId, uint tradeId, address, AssetDelta[] calldata assetDeltas, bytes memory)
    public
  {
    // TODO: ignore when only adding non-risky assets
    _chargeOIFee(accountId, tradeId, assetDeltas);

    NewPortfolio memory portfolio = _arrangePortfolio(accounts.getAccountBalances(accountId));

    _checkMargin(portfolio);
  }

  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

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
    portfolio.spotPrice = spotFeed.getSpot();
    for (uint i = 0; i < seenExpiries; ++i) {
      portfolio.expiries[i] = ExpiryHoldings({
        expiry: expiryCount[i].expiry,
        calls: new StrikeHolding[](expiryCount[i].callCount),
        puts: new StrikeHolding[](expiryCount[i].putCount),
        forwardPrice: futureFeed.getFuturePrice(expiryCount[i].expiry)
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
          expiry.calls[--expiryCount[expiryIndex].callCount] = StrikeHolding({
            strike: strike,
            vol: 1e18, // TODO: vol feed
            amount: currentAsset.balance
          });
        } else {
          expiry.puts[--expiryCount[expiryIndex].putCount] = StrikeHolding({
            strike: strike,
            vol: 1e18, // TODO: vol feed
            amount: currentAsset.balance
          });
        }
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
      } else {
        otherAssetCount++;
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

    _addSIVs(portfolio);

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

  /////////////////////////////////
  // Scenario independent values //
  /////////////////////////////////

  uint constant epsilon = 0.05e18;
  uint constant fwdStep = 0.01e18;

  function _addSIVs(NewPortfolio memory portfolio) internal view {
    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      ExpiryHoldings memory expiry = portfolio.expiries[i];
      // Get MtM
      int expiryMTM = _getExpiryShockedMTM(expiry, Scenario({spotShock: 1e18, volShock: 1e18}));
      portfolio.mtm += expiryMTM;
      // TODO: 1.05 == epsilon
      int fwdUp = _getExpiryShockedMTM(expiry, Scenario({spotShock: DecimalMath.UNIT + epsilon, volShock: 1e18}));
      portfolio.fwdLosses += -int(IntLib.abs(fwdUp - expiryMTM) * fwdStep / epsilon);
      portfolio.shortOptionContingency += _calcShortOptionContingency(expiry);
    }
  }

  int constant netPosScalar = 0.01e18;

  function _calcShortOptionContingency(ExpiryHoldings memory expiry) internal view returns (int) {
    int netShortPosPerStrike = 0;
    bool[] memory seenPuts = new bool[](expiry.puts.length);
    for (uint i = 0; i < expiry.calls.length; ++i) {
      StrikeHolding memory call = expiry.calls[i];
      for (uint j = 0; j < expiry.puts.length; ++j) {
        StrikeHolding memory put = expiry.puts[j];
        if (put.strike == call.strike) {
          seenPuts[j] = true;
          int tot = call.amount + put.amount;
          netShortPosPerStrike += tot < 0 ? tot : int(0);
        }
      }
    }
    return netShortPosPerStrike * netPosScalar / 1e18 * int(expiry.forwardPrice) / 1e18;
  }

  ////////////////////////
  // get Initial Margin //
  ////////////////////////

  // TODO: exponential and time to expiry
  int constant staticDiscount = 0.9e18;
  int constant lossFactor = 1.3e18;

  function _getIM(NewPortfolio memory portfolio) internal view returns (int) {
    int minMargin = type(int).max;

    // TODO: better to iterate over spot shocks and vol shocks separately - save on computing otherAsset value
    for (uint i = 0; i < scenarios.length; ++i) {
      Scenario memory scenario = scenarios[i];

      int scenarioMTM = 0;

      // todo: use portfolio.mtm for scenario == 0 spot, 0 vol shock
      if (scenario.volShock == 1e18 && scenario.spotShock == 1e18) {
        scenarioMTM += _applyMTMDiscount(portfolio.mtm);
      } else {
        for (uint j = 0; j < portfolio.expiries.length; ++j) {
          ExpiryHoldings memory expiry = portfolio.expiries[j];
          scenarioMTM += _applyMTMDiscount(_getExpiryShockedMTM(expiry, scenario));
        }
      }

      int scenarioLoss =
        (scenarioMTM - portfolio.mtm + portfolio.fwdLosses + portfolio.shortOptionContingency) * lossFactor / 1e18;

      int otherAssetValue;
      for (uint j = 0; j < portfolio.otherAssets.length; ++j) {
        OtherAsset memory otherAsset = portfolio.otherAssets[j];
        if (otherAsset.asset == address(0xf00f00)) {
          // PERPS
          // TODO: unrealised pnl too when possible to get
          int pnl = int(portfolio.spotPrice * scenario.spotShock / 1e18) - int(portfolio.spotPrice);
          otherAssetValue += otherAsset.amount * pnl / 1e18;
        } else if (otherAsset.asset == address(0xbaabaa)) {
          // wETH
          int value = int(portfolio.spotPrice * scenario.spotShock / 1e18);
          otherAssetValue += otherAsset.amount * value / 1e18;
        } else {
          revert("invalid other asset");
        }
      }
      scenarioMTM += otherAssetValue + scenarioLoss;

      if (scenarioMTM < minMargin) {
        minMargin = scenarioMTM;
      }
    }

    if (minMargin > 0) {
      return 0;
    }
    return minMargin;
  }

  function _checkMargin(NewPortfolio memory portfolio) internal view {
    int im = _getIM(portfolio);
    int margin = portfolio.cash + im;
    if (margin < 0) {
      revert("Not enough margin");
    }
  }

  function _applyMTMDiscount(int expiryMTM) internal pure returns (int) {
    if (expiryMTM > 0) {
      // TODO: * e^-shockRFR*TimeToExpiry
      return expiryMTM * staticDiscount / 1e18;
    } else {
      return expiryMTM;
    }
  }

  /////////////
  // Helpers //
  /////////////

  // calculate MTM with given shock
  function _getExpiryShockedMTM(ExpiryHoldings memory expiry, Scenario memory scenario) internal view returns (int mtm) {
    mtm = 0;
    // Iterate over all the calls in the expiry
    for (uint i = 0; i < expiry.calls.length; i++) {
      StrikeHolding memory call = expiry.calls[i];
      // Calculate the black scholes value of the call
      mtm += mtmCache.getMTM(
        call.strike,
        expiry.expiry,
        expiry.forwardPrice,
        call.vol,
        0.06e18, // TODO: interest rate feed
        call.amount,
        true
      );
    }

    // Iterate over all the puts in the expiry
    for (uint i = 0; i < expiry.puts.length; i++) {
      StrikeHolding memory put = expiry.puts[i];
      // Calculate the black scholes value of the put
      mtm += mtmCache.getMTM(
        put.strike,
        expiry.expiry,
        expiry.forwardPrice,
        put.vol,
        0.06e18, // TODO: interest rate feed
        put.amount,
        false
      );
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

  function getIM(IAccounts.AssetBalance[] memory assets) external view returns (int) {
    console2.log("total assets", assets.length);
    NewPortfolio memory portfolio = _arrangePortfolio(assets);
    int im = _getIM(portfolio);
    console2.log("im", im);
    return im;
  }

  ////////////
  // Errors //
  ////////////

  error PCRM_OnlyAuction();

  error PCRM_InvalidBidPortion();

  error PCRM_MarginRequirementNotMet(int initMargin);

  error PCRM_InvalidMarginParam();
}
