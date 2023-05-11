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
  uint public constant MAX_ASSETS = 32;

  ///////////////
  // Variables //
  ///////////////

  /// @dev Spot price oracle
  ISpotFeed public spotFeed;
  IInterestRateFeed public interestRateFeed;
  IVolFeed public volFeed;
  ISpotFeed public stableFeed;

  WrappedERC20Asset public immutable baseAsset;

  /// @dev Portfolio Margin Parameters: maintenance and initial margin requirements
  IPMRM.PMRMParameters public pmrmParams;
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
    IForwardFeed futureFeed_,
    ISettlementFeed settlementFeed_,
    ISpotFeed spotFeed_,
    IMTMCache mtmCache_,
    IInterestRateFeed interestRateFeed_,
    IVolFeed volFeed_,
    WrappedERC20Asset baseAsset_,
    ISpotFeed stableFeed_
  ) PMRMLib(mtmCache_) BaseManager(accounts_, futureFeed_, settlementFeed_, cashAsset_, option_, perp_) {
    spotFeed = spotFeed_;
    interestRateFeed = interestRateFeed_;
    volFeed = volFeed_;
    baseAsset = baseAsset_;
    stableFeed = stableFeed_;

    pmrmParams.pegLossFactor = 0.5e18;
  }

  ////////////////////////
  //    Admin-Only     //
  ///////////////////////

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

  function setPMRMParameters(IPMRM.PMRMParameters memory _pmrmParameters) external onlyOwner {
    pmrmParams = _pmrmParameters;
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
   * @notice Ensures asset is valid and Max Loss margin is met.
   * @param accountId Account for which to check trade.
   */
  function handleAdjustment(
    uint accountId,
    uint tradeId,
    address caller,
    IAccounts.AssetDelta[] calldata assetDeltas,
    bytes memory
  ) public onlyAccounts {
    _chargeOIFee(accountId, tradeId, assetDeltas);

    // check assets are only cash and perp
    for (uint i = 0; i < assetDeltas.length; i++) {
      if (assetDeltas[i].asset == perp) {
        // settle perps if the user has perp position
        _settleAccountPerps(accountId);
      } else if (assetDeltas[i].asset != cashAsset && assetDeltas[i].asset != option) {
        revert("unsupported asset");
      }
    }

    bool isTrustedRiskAssessor = trustedRiskAssessor[caller];

    IPMRM.PMRM_Portfolio memory portfolio =
      _arrangePortfolio(accountId, accounts.getAccountBalances(accountId), !isTrustedRiskAssessor);

    if (isTrustedRiskAssessor) {
      IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](1);
      scenarios[0] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.None});
      _checkMargin(portfolio, scenarios);
    } else {
      _checkMargin(portfolio, marginScenarios);
    }
  }

  ///////////////////////
  // Arrange Portfolio //
  ///////////////////////

  function _initialiseExpiries(IPMRM.PMRM_Portfolio memory portfolio, PortfolioExpiryData[] memory expiryCount)
    internal
    view
  {
    for (uint i = 0; i < portfolio.expiries.length; ++i) {
      (uint forwardPrice, uint confidence1) = futureFeed.getForwardPrice(expiryCount[i].expiry);
      // TODO: rate feed and convert to discount factor
      (int64 rate, uint confidence2) = interestRateFeed.getInterestRate(expiryCount[i].expiry);
      uint minConfidence = confidence1 < confidence2 ? confidence1 : confidence2;
      minConfidence = portfolio.minConfidence < minConfidence ? portfolio.minConfidence : minConfidence;

      uint secToExpiry = expiryCount[i].expiry - block.timestamp;
      portfolio.expiries[i] = ExpiryHoldings({
        secToExpiry: SafeCast.toUint64(secToExpiry),
        options: new StrikeHolding[](expiryCount[i].optionCount),
        forwardPrice: forwardPrice,
        // vol shocks are added in addPrecomputes
        volShockUp: 0,
        volShockDown: 0,
        mtm: 0,
        fwdShock1MtM: 0,
        fwdShock2MtM: 0,
        staticDiscount: 0,
        rate: int64(rate),
        discountFactor: _getDiscountFactor(rate, secToExpiry),
        minConfidence: minConfidence,
        netOptions: 0
      });
    }
  }

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
    _initialiseExpiries(portfolio, expiryCount);

    // TODO: stable confidence?
    // TODO: depeg contingency
    (portfolio.stablePrice,) = stableFeed.getSpot();

    for (uint i = 0; i < assets.length; ++i) {
      IAccounts.AssetBalance memory currentAsset = assets[i];
      if (address(currentAsset.asset) == address(option)) {
        (uint optionExpiry, uint strike, bool isCall) = OptionEncoding.fromSubId(SafeCast.toUint96(currentAsset.subId));

        uint expiryIndex = findInArray(portfolio.expiries, optionExpiry - block.timestamp, portfolio.expiries.length);

        ExpiryHoldings memory expiry = portfolio.expiries[expiryIndex];

        // insert the calls at the front, and the puts at the end of the options array
        uint index = --expiryCount[expiryIndex].optionCount;

        (uint vol, uint confidence) = volFeed.getVol(SafeCast.toUint128(strike), SafeCast.toUint128(optionExpiry));
        expiry.netOptions += IntLib.abs(currentAsset.balance);
        if (confidence < expiry.minConfidence) {
          expiry.minConfidence = confidence;
        }
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
          expiryCount[seenExpiries++] = PortfolioExpiryData({expiry: optionExpiry, optionCount: 1});
        }
      }
    }

    return (seenExpiries, expiryCount);
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

  //////
  //
  ////

  function _checkMargin(IPMRM.PMRM_Portfolio memory portfolio, IPMRM.Scenario[] memory scenarios) internal view {
    int im = _getMargin(portfolio, true, scenarios);
    int margin = portfolio.cash + im;
    if (margin < 0) {
      revert("IM rules not satisfied");
    }
  }

  /////////////
  // Helpers //
  /////////////

  //////////
  // View //
  //////////

  function arrangePortfolio(IAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IPMRM.PMRM_Portfolio memory portfolio)
  {
    // TODO: pass in account Id
    return _arrangePortfolio(0, assets, true);
  }

  function getMargin(IAccounts.AssetBalance[] memory assets, bool isInitial) external view returns (int) {
    // TODO: pass in account Id
    IPMRM.PMRM_Portfolio memory portfolio = _arrangePortfolio(0, assets, true);
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
