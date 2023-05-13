// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/math/IntLib.sol";
import "lyra-utils/math/FixedPointMathLib.sol";
import "lyra-utils/ownership/Owned.sol";

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
import "./PMRMLib.sol";
import "../assets/WrappedERC20Asset.sol";

/**
 * @title PMRM
 * @author Lyra
 * @notice Risk Manager that uses a SPAN like methodology to margin an options portfolio.
 */

contract PMRM is PMRMLib, IPMRM, BaseManager {
  using SignedDecimalMath for int;
  using DecimalMath for uint;
  using SafeCast for uint;
  using IntLib for int;

  ///////////////
  // Constants //
  ///////////////
  uint public constant MAX_EXPIRIES = 11;
  uint public constant MAX_ASSETS = 1024; // TODO: limit

  ///////////////
  // Variables //
  ///////////////

  ISpotFeed public spotFeed;
  IInterestRateFeed public interestRateFeed;
  IVolFeed public volFeed;
  ISpotFeed public stableFeed;
  IForwardFeed public forwardFeed;
  ISettlementFeed public settlementFeed;
  IOption public option;
  IPerpAsset public perp;

  WrappedERC20Asset public immutable baseAsset;

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
    IForwardFeed forwardFeed_,
    ISettlementFeed settlementFeed_,
    ISpotFeed spotFeed_,
    IMTMCache mtmCache_,
    IInterestRateFeed interestRateFeed_,
    IVolFeed volFeed_,
    WrappedERC20Asset baseAsset_,
    ISpotFeed stableFeed_
  ) PMRMLib(mtmCache_) BaseManager(accounts_, cashAsset_) {
    spotFeed = spotFeed_;
    interestRateFeed = interestRateFeed_;
    volFeed = volFeed_;
    baseAsset = baseAsset_;
    stableFeed = stableFeed_;
    forwardFeed = forwardFeed_;
    settlementFeed = settlementFeed_;
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

    for (uint i = _scenarios.length; i < marginScenarios.length; i++) {
      marginScenarios.pop();
    }
  }

  function setInterestRateFeed(IInterestRateFeed _interestRateFeed) external onlyOwner {
    interestRateFeed = _interestRateFeed;
  }

  function setVolFeed(IVolFeed _volFeed) external onlyOwner {
    volFeed = _volFeed;
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

    for (uint i = 0; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset == perp) {
        // Settle perps if the user has a perp position
        _settleAccountPerps(perp, accountId);
      } else if (
        assetDeltas[i].asset != cashAsset && assetDeltas[i].asset != option && assetDeltas[i].asset != baseAsset
      ) {
        revert("unsupported asset");
      }
    }

    bool isTrustedRiskAssessor = trustedRiskAssessor[caller];

    IPMRM.PMRM_Portfolio memory portfolio =
      _arrangePortfolio(accountId, accounts.getAccountBalances(accountId), !isTrustedRiskAssessor);

    if (isTrustedRiskAssessor) {
      // If the caller is a trusted risk assessor, use a single predefined scenario for checking margin
      IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](1);
      scenarios[0] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.None});
      _checkMargin(portfolio, scenarios);
    } else {
      // If the caller is not a trusted risk assessor, use all the margin scenarios
      _checkMargin(portfolio, marginScenarios);
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
    returns (IPMRM.PMRM_Portfolio memory portfolio)
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

    seenExpiries = 0;
    expiryCount = new IPMRM.PortfolioExpiryData[](MAX_EXPIRIES > assetLen ? assetLen : MAX_EXPIRIES);

    // Just count the number of options per expiry
    for (uint i = 0; i < assetLen; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry,, bool isCall) = OptionEncoding.fromSubId(uint96(currentAsset.subId));
        if (optionExpiry < block.timestamp) {
          revert("option expired");
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
            revert("Too many expiries");
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
  function _initialiseExpiries(IPMRM.PMRM_Portfolio memory portfolio, PortfolioExpiryData[] memory expiryCount)
    internal
    view
  {
    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      (uint forwardPrice, uint confidence1) = forwardFeed.getForwardPrice(expiryCount[i].expiry);
      (int64 rate, uint confidence2) = interestRateFeed.getInterestRate(expiryCount[i].expiry);
      uint minConfidence = confidence1 < confidence2 ? confidence1 : confidence2;
      minConfidence = portfolio.minConfidence < minConfidence ? portfolio.minConfidence : minConfidence;

      uint secToExpiry = expiryCount[i].expiry - block.timestamp;
      portfolio.expiries[i] = ExpiryHoldings({
        secToExpiry: SafeCast.toUint64(secToExpiry),
        options: new StrikeHolding[](expiryCount[i].optionCount),
        forwardPrice: forwardPrice,
        rate: SafeCast.toInt64(rate),
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
    IPMRM.PMRM_Portfolio memory portfolio,
    IAccounts.AssetBalance[] memory assets,
    PortfolioExpiryData[] memory expiryCount
  ) internal view {
    for (uint i = 0; i < assets.length; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(currentAsset.subId));

        uint expiryIndex = findInArray(portfolio.expiries, optionExpiry - block.timestamp, portfolio.expiries.length);

        ExpiryHoldings memory expiry = portfolio.expiries[expiryIndex];

        (uint vol, uint confidence) = volFeed.getVol(SafeCast.toUint128(strike), SafeCast.toUint128(optionExpiry));
        if (confidence < expiry.minConfidence) {
          expiry.minConfidence = confidence;
        }

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
        portfolio.basePosition = SafeCast.toUint256(currentAsset.balance);
      } else {
        revert("Invalid asset type");
      }
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
      revert("secToExpiry not found");
    }
  }

  function _checkMargin(IPMRM.PMRM_Portfolio memory portfolio, IPMRM.Scenario[] memory scenarios) internal view {
    int im = _getMargin(portfolio, true, scenarios);
    if (im < 0) {
      revert("IM rules not satisfied");
    }
  }

  //////////
  // View //
  //////////

  function arrangePortfolio(uint accountId) external view returns (IPMRM.PMRM_Portfolio memory portfolio) {
    return _arrangePortfolio(0, accounts.getAccountBalances(accountId), true);
  }

  function getMargin(uint accountId, bool isInitial) external view returns (int) {
    IPMRM.PMRM_Portfolio memory portfolio = _arrangePortfolio(0, accounts.getAccountBalances(accountId), true);
    int im = _getMargin(portfolio, isInitial, marginScenarios);
    return im;
  }

  function mergeAccounts(uint mergeIntoId, uint[] memory mergeFromIds) external {
    address owner = accounts.ownerOf(mergeIntoId);
    for (uint i = 0; i < mergeFromIds.length; ++i) {
      // check owner of all accounts is the same - note this ignores
      if (owner != accounts.ownerOf(mergeFromIds[i])) {
        revert("accounts not owned by same address");
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

  ////////////////////////
  //    Account Hooks   //
  ////////////////////////

  /**
   * @notice Ensures new manager is valid.
   * @param newManager IManager to change account to.
   */
  function handleManagerChange(uint, IManager newManager) external view {}

  ////////////////////////
  //      Modifiers     //
  ////////////////////////

  modifier onlyAccounts() {
    if (msg.sender != address(accounts)) {
      revert("only accounts");
    }
    _;
  }
}
