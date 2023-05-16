// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/IntLib.sol";
import "lyra-utils/math/FixedPointMathLib.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IPerpAsset.sol";
import "src/interfaces/IBaseManager.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/IOptionPricing.sol";
import "src/interfaces/ISpotFeed.sol";
import "src/interfaces/IBasicManager.sol";
import "src/interfaces/IVolFeed.sol";
import "src/interfaces/IInterestRateFeed.sol";
import "src/interfaces/IPMRM.sol";

import "./BaseManager.sol";

import "forge-std/console2.sol";
import "src/risk-managers/PMRMLib.sol";
import "src/assets/WrappedERC20Asset.sol";

/**
 * @title PMRM
 * @author Lyra
 * @notice Risk Manager that uses a SPAN like methodology to margin an options portfolio.
 */

contract PMRM is PMRMLib, IPMRM, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;
  using IntLib for int;

  ///////////////
  // Constants //
  ///////////////
  uint public constant MAX_EXPIRIES = 11;
  uint public constant MAX_ASSETS = 128;

  ///////////////
  // Variables //
  ///////////////

  IOption public immutable option;
  IPerpAsset public immutable perp;
  WrappedERC20Asset public immutable baseAsset;

  ISpotFeed public spotFeed;
  IInterestRateFeed public interestRateFeed;
  IVolFeed public volFeed;
  ISpotFeed public stableFeed;
  IForwardFeed public forwardFeed;
  ISettlementFeed public settlementFeed;

  IPMRM.Scenario[] public marginScenarios;

  mapping(address => bool) public trustedRiskAssessor;

  ////////////////////////
  //    Constructor     //
  ////////////////////////

  constructor(
    IAccounts accounts_,
    ICashAsset cashAsset_,
    IOption option_,
    IPerpAsset perp_,
    IOptionPricing optionPricing_,
    WrappedERC20Asset baseAsset_,
    Feeds memory feeds_
  ) PMRMLib(optionPricing_) BaseManager(accounts_, cashAsset_, IDutchAuction(address(0))) {
    spotFeed = feeds_.spotFeed;
    stableFeed = feeds_.stableFeed;
    forwardFeed = feeds_.forwardFeed;
    interestRateFeed = feeds_.interestRateFeed;
    volFeed = feeds_.volFeed;
    settlementFeed = feeds_.settlementFeed;

    baseAsset = baseAsset_;
    option = option_;
    perp = perp_;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

  /**
   * @notice Sets the scenarios for managing margin positions.
   * @dev Only the contract owner can invoke this function.
   * @param _scenarios An array of Scenario structs representing the margin scenarios.
   *                   Each Scenario struct contains relevant data for a specific scenario.
   */
  function setScenarios(IPMRM.Scenario[] memory _scenarios) external onlyOwner {
    for (uint i = 0; i < _scenarios.length; i++) {
      if (marginScenarios.length <= i) {
        marginScenarios.push(_scenarios[i]);
      } else {
        marginScenarios[i] = _scenarios[i];
      }
    }

    uint marginScenariosLength = marginScenarios.length;
    for (uint i = _scenarios.length; i < marginScenariosLength; i++) {
      marginScenarios.pop();
    }
  }

  function setInterestRateFeed(IInterestRateFeed _interestRateFeed) external onlyOwner {
    interestRateFeed = _interestRateFeed;
  }

  function setVolFeed(IVolFeed _volFeed) external onlyOwner {
    volFeed = _volFeed;
  }

  function setSpotFeed(ISpotFeed _spotFeed) external onlyOwner {
    spotFeed = _spotFeed;
  }

  function setStableFeed(ISpotFeed _stableFeed) external onlyOwner {
    stableFeed = _stableFeed;
  }

  function setForwardFeed(IForwardFeed _forwardFeed) external onlyOwner {
    forwardFeed = _forwardFeed;
  }

  function setSettlementFeed(ISettlementFeed _settlementFeed) external onlyOwner {
    settlementFeed = _settlementFeed;
  }

  function setTrustedRiskAssessor(address riskAssessor, bool trusted) external onlyOwner {
    trustedRiskAssessor[riskAssessor] = trusted;
  }

  ///////////////////////
  //   Account Hooks   //
  ///////////////////////

  /**
   * @notice Handles adjustments to the margin positions for a given account.
   * @dev Only the accounts contract can invoke this function.
   * @param accountId The ID of the account.
   * @param tradeId The ID of the trade.
   * @param caller The address of the caller.
   * @param assetDeltas An array of AssetDelta structs representing changes to account assets.
   * @param managerData Additional data (unused in this function).
   */
  function handleAdjustment(
    uint accountId,
    uint tradeId,
    address caller,
    IAccounts.AssetDelta[] calldata assetDeltas,
    bytes memory managerData
  ) public onlyAccounts {
    _chargeOIFee(option, forwardFeed, accountId, tradeId, assetDeltas);

    bool riskAdding = false;
    for (uint i = 0; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset == perp) {
        // Settle perps if the user has a perp position
        _settleAccountPerps(perp, accountId);
        riskAdding = true;
      } else if (
        assetDeltas[i].asset != cashAsset && assetDeltas[i].asset != option && assetDeltas[i].asset != baseAsset
      ) {
        revert PMRM_UnsupportedAsset();
      } else {
        if (assetDeltas[i].delta < 0) {
          riskAdding = true;
        }
      }
    }

    if (!riskAdding) {
      // Early exit if only adding cash/option/baseAsset
      return;
    }

    bool isTrustedRiskAssessor = trustedRiskAssessor[caller];

    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);
    IPMRM.Portfolio memory portfolio = _arrangePortfolio(accountId, assetBalances, !isTrustedRiskAssessor);

    if (isTrustedRiskAssessor) {
      // If the caller is a trusted risk assessor, use a single predefined scenario for checking margin
      IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](1);
      scenarios[0] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.None});
      int atmMM = _getMargin(portfolio, false, scenarios, false);
      if (atmMM + portfolio.cash < 0) {
        revert PMRM_InsufficientMargin();
      }
    } else {
      // If the caller is not a trusted risk assessor, use all the margin scenarios
      int postIM = _getMargin(portfolio, true, marginScenarios, true);
      if (postIM + portfolio.cash < 0) {
        // Note: cash interest is also undone here, but this is not a significant issue
        IPMRM.Portfolio memory prePortfolio =
          _arrangePortfolio(accountId, undoAssetDeltas(accountId, assetDeltas), !isTrustedRiskAssessor);

        int preIM = _getMargin(prePortfolio, true, marginScenarios, true);
        if (postIM < preIM) {
          revert PMRM_InsufficientMargin();
        }
      }
    }
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
  function _arrangePortfolio(uint accountId, IAccounts.AssetBalance[] memory assets, bool addForwardCont)
    internal
    view
    returns (IPMRM.Portfolio memory portfolio)
  {
    (uint seenExpiries, PortfolioExpiryData[] memory expiryCount) = _countExpiriesAndOptions(assets);

    portfolio.expiries = new ExpiryHoldings[](seenExpiries);
    (portfolio.spotPrice, portfolio.minConfidence) = spotFeed.getSpot();

    (uint stablePrice, uint stableConfidence) = stableFeed.getSpot();
    if (stableConfidence < portfolio.minConfidence) {
      portfolio.minConfidence = stableConfidence;
    }
    portfolio.stablePrice = stablePrice;

    _initialiseExpiries(portfolio, expiryCount);
    _arrangeOptions(accountId, portfolio, assets, expiryCount);
    _addPrecomputes(portfolio, addForwardCont);

    return portfolio;
  }

  function _countExpiriesAndOptions(IAccounts.AssetBalance[] memory assets)
    internal
    view
    returns (uint seenExpiries, IPMRM.PortfolioExpiryData[] memory expiryCount)
  {
    uint assetLen = assets.length;

    if (assetLen > MAX_ASSETS) {
      revert PMRM_TooManyAssets();
    }

    seenExpiries = 0;
    expiryCount = new IPMRM.PortfolioExpiryData[](MAX_EXPIRIES > assetLen ? assetLen : MAX_EXPIRIES);

    // Just count the number of options per expiry
    for (uint i = 0; i < assetLen; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry,, bool isCall) = OptionEncoding.fromSubId(currentAsset.subId.toUint96());
        if (optionExpiry < block.timestamp) {
          revert PMRM_OptionExpired();
        }

        bool found = false;
        for (uint j = 0; j < seenExpiries; j++) {
          if (expiryCount[j].expiry == optionExpiry) {
            expiryCount[j].optionCount++;
            found = true;
            break;
          }
        }
        if (!found) {
          if (seenExpiries == MAX_EXPIRIES) {
            revert PMRM_TooManyExpiries();
          }
          expiryCount[seenExpiries++] = PortfolioExpiryData({expiry: optionExpiry, optionCount: 1});
        }
      }
    }

    return (seenExpiries, expiryCount);
  }

  /**
   *
   */
  function _initialiseExpiries(IPMRM.Portfolio memory portfolio, PortfolioExpiryData[] memory expiryCount)
    internal
    view
  {
    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      (uint forwardFixedPortion, uint forwardVariablePortion, uint fwdConfidence) =
        forwardFeed.getForwardPricePortions(expiryCount[i].expiry);
      (int64 rate, uint rateConfidence) = interestRateFeed.getInterestRate(expiryCount[i].expiry);
      uint minConfidence = UintLib.min(fwdConfidence, rateConfidence);
      minConfidence = UintLib.min(portfolio.minConfidence, minConfidence);

      uint secToExpiry = expiryCount[i].expiry - block.timestamp;
      portfolio.expiries[i] = ExpiryHoldings({
        secToExpiry: secToExpiry.toUint64(),
        options: new StrikeHolding[](expiryCount[i].optionCount),
        forwardFixedPortion: forwardFixedPortion,
        forwardVariablePortion: forwardVariablePortion,
        rate: rate,
        minConfidence: minConfidence,
        netOptions: 0,
        // vol shocks are added in addPrecomputes
        mtm: 0,
        fwdShock1MtM: 0,
        fwdShock2MtM: 0,
        volShockUp: 0,
        volShockDown: 0,
        staticDiscount: 0
      });
    }
  }

  function _arrangeOptions(
    uint accountId,
    IPMRM.Portfolio memory portfolio,
    IAccounts.AssetBalance[] memory assets,
    PortfolioExpiryData[] memory expiryCount
  ) internal view {
    for (uint i = 0; i < assets.length; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry, uint strike, bool isCall) = OptionEncoding.fromSubId(currentAsset.subId.toUint96());

        uint expiryIndex = findInArray(portfolio.expiries, optionExpiry - block.timestamp, portfolio.expiries.length);

        ExpiryHoldings memory expiry = portfolio.expiries[expiryIndex];

        (uint vol, uint confidence) = volFeed.getVol(strike.toUint128(), optionExpiry.toUint128());

        expiry.minConfidence = UintLib.min(confidence, expiry.minConfidence);

        expiry.netOptions += IntLib.abs(currentAsset.balance);

        uint index = --expiryCount[expiryIndex].optionCount;
        expiry.options[index] =
          StrikeHolding({strike: strike, vol: vol, amount: currentAsset.balance, isCall: isCall, seenInFilter: false});
      } else if (address(currentAsset.asset) == address(cashAsset)) {
        portfolio.cash = currentAsset.balance;
      } else if (address(currentAsset.asset) == address(perp)) {
        portfolio.perpPosition = currentAsset.balance;
        portfolio.unrealisedPerpValue = perp.getUnsettledAndUnrealizedCash(accountId);
      } else if (address(currentAsset.asset) == address(baseAsset)) {
        portfolio.basePosition = currentAsset.balance.toUint256();
      } // No need to catch other assets, as they will be caught in handleAdjustment
    }
  }

  function findInArray(ExpiryHoldings[] memory expiryData, uint secToExpiryToFind, uint arrayLen)
    internal
    pure
    returns (uint index)
  {
    unchecked {
      for (uint i; i < arrayLen; ++i) {
        if (expiryData[i].secToExpiry == secToExpiryToFind) {
          return i;
        }
      }
      revert PMRM_FindInArrayError();
    }
  }

  //////////
  // View //
  //////////

  function getScenarios() external view returns (IPMRM.Scenario[] memory) {
    return marginScenarios;
  }

  function arrangePortfolio(uint accountId) external view returns (IPMRM.Portfolio memory portfolio) {
    return _arrangePortfolio(0, accounts.getAccountBalances(accountId), true);
  }

  function getMargin(uint accountId, bool isInitial) external view returns (int) {
    IPMRM.Portfolio memory portfolio = _arrangePortfolio(0, accounts.getAccountBalances(accountId), true);
    return _getMargin(portfolio, isInitial, marginScenarios, true);
  }

  function mergeAccounts(uint mergeIntoId, uint[] memory mergeFromIds) external {
    address owner = accounts.ownerOf(mergeIntoId);
    for (uint i = 0; i < mergeFromIds.length; ++i) {
      // check owner of all accounts is the same - note this ignores
      if (owner != accounts.ownerOf(mergeFromIds[i])) {
        revert PMRM_MergeOwnerMismatch();
      }
      // Move all assets of the other
      IAccounts.AssetBalance[] memory assets = accounts.getAccountBalances(mergeFromIds[i]);
      for (uint j = 0; j < assets.length; ++j) {
        _symmetricManagerAdjustment(
          mergeFromIds[i], mergeIntoId, assets[j].asset, SafeCast.toUint96(assets[j].subId), assets[j].balance
        );
      }
    }
  }

  //////////
  // Misc //
  //////////

  function undoAssetDeltas(uint accountId, IAccounts.AssetDelta[] memory assetDeltas)
    internal
    view
    returns (IAccounts.AssetBalance[] memory newAssetBalances)
  {
    IAccounts.AssetBalance[] memory assetBalances = accounts.getAccountBalances(accountId);

    // keep track of how many new elements to add to the result. Can be negative (remove balances that end at 0)
    uint removedBalances = 0;
    uint newBalances = 0;
    IAccounts.AssetBalance[] memory preBalances = new IAccounts.AssetBalance[](assetDeltas.length);

    for (uint i = 0; i < assetDeltas.length; ++i) {
      IAccounts.AssetDelta memory delta = assetDeltas[i];
      if (delta.delta == 0) {
        continue;
      }
      bool found = false;
      for (uint j = 0; j < assetBalances.length; ++j) {
        IAccounts.AssetBalance memory balance = assetBalances[j];
        if (balance.asset == delta.asset && balance.subId == delta.subId) {
          found = true;
          assetBalances[j].balance = balance.balance - delta.delta;
          if (assetBalances[j].balance == 0) {
            removedBalances++;
          }
          break;
        }
      }
      if (!found) {
        preBalances[newBalances++] =
          IAccounts.AssetBalance({asset: delta.asset, subId: delta.subId, balance: -delta.delta});
      }
    }

    newAssetBalances = new IAccounts.AssetBalance[](assetBalances.length + newBalances - removedBalances);

    uint newBalancesIndex = 0;
    for (uint i = 0; i < assetBalances.length; ++i) {
      IAccounts.AssetBalance memory balance = assetBalances[i];
      if (balance.balance != 0) {
        newAssetBalances[newBalancesIndex++] = balance;
      }
    }
    for (uint i = 0; i < newBalances; ++i) {
      newAssetBalances[newBalancesIndex++] = preBalances[i];
    }

    return newAssetBalances;
  }
}
