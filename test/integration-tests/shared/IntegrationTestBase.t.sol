// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../src/SecurityModule.sol";
import "../../../src/assets/CashAsset.sol";
import "../../../src/assets/Option.sol";
import "../../../src/assets/PerpAsset.sol";
import "../../../src/assets/InterestRateModel.sol";

import "../../../src/assets/WrappedERC20Asset.sol";

import "../../../src/liquidation/DutchAuction.sol";
import "../../../src/SubAccounts.sol";

import "../../../src/risk-managers/StandardManager.sol";
import "../../../src/risk-managers/PMRM.sol";
import "../../../src/risk-managers/SRMPortfolioViewer.sol";

import "../../../src/feeds/OptionPricing.sol";

import "../../shared/mocks/MockFeeds.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../../src/feeds/LyraSpotDiffFeed.sol";
import "../../../src/feeds/LyraRateFeed.sol";

import "../../../src/feeds/LyraSpotFeed.sol";
import "../../../src/feeds/LyraVolFeed.sol";
import "../../../src/feeds/LyraForwardFeed.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

import {IPMRMLib} from "../../../src/interfaces/IPMRMLib.sol";
import {IBaseManager} from "../../../src/interfaces/IBaseManager.sol";

import "../../../scripts/config.sol";

/**
 * @dev real Accounts contract
 * @dev real CashAsset contract
 * @dev real SecurityModule contract
 */
contract IntegrationTestBase is Test {
  uint keeperPk = 0xBEEFDEAD;
  address keeper = vm.addr(keeperPk);

  address alice = address(0xa11ce);
  address bob = address(0xb0b);
  uint aliceAcc;
  uint bobAcc;

  uint smAcc;

  uint public constant DEFAULT_DEPOSIT = 5000e18;
  int public constant ETH_PRICE = 2000e18;

  struct Market {
    uint8 id;
    MockERC20 erc20;
    // lyra asset
    Option option;
    PerpAsset perp;
    WrappedERC20Asset base;
    // feeds
    LyraSpotFeed spotFeed;
    LyraSpotDiffFeed perpFeed;
    LyraSpotDiffFeed iapFeed;
    LyraSpotDiffFeed ibpFeed;
    LyraVolFeed volFeed;
    LyraRateFeed rateFeed;
    LyraForwardFeed forwardFeed;
    // pricing
    OptionPricing pricing;
    // manager for specific market
    PMRM pmrm;
    PMRMLib pmrmLib;
    BasePortfolioViewer pmrmViewer;
  }

  SubAccounts public subAccounts;
  MockERC20 public usdc;
  MockERC20 public weth;

  // Lyra Assets
  CashAsset public cash;

  SecurityModule public securityModule;
  InterestRateModel public rateModel;
  DutchAuction public auction;

  // Single standard manager shared across all markets
  StandardManager public srm;
  SRMPortfolioViewer public portfolioViewer;

  MockFeeds internal stableFeed;

  uint8 internal nextId = 1;

  mapping(string => Market) internal markets;

  function _setupIntegrationTestComplete() internal {
    // deploy Accounts, cash, security module, auction
    _deployV2Core();
    _setupCoreContracts();

    _deployMarket("weth", 2000e18);
    _deployMarket("wbtc", 25000e18);

    // create accounts, controlled by standard manager
    _setupAliceAndBob();
  }

  function _setupAliceAndBob() internal {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    aliceAcc = subAccounts.createAccountWithApproval(alice, address(this), srm);
    bobAcc = subAccounts.createAccountWithApproval(bob, address(this), srm);
  }

  function _deployV2Core() internal {
    // Nonce 1: Deploy Accounts
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    // Nonce 2: Deploy USDC
    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    // Nonce 3: Deploy RateModel
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = _getDefaultRateModelParam();
    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // Nonce 4: Deploy CashAsset
    cash = new CashAsset(subAccounts, usdc, rateModel);

    // Nonce 5: Deploy SM
    address srmAddr = _predictAddress(address(this), 8);
    securityModule = new SecurityModule(subAccounts, cash, IManager(srmAddr));

    // Nonce 6: Deploy Auction
    auction = new DutchAuction(subAccounts, securityModule, cash);

    // Nonce 7: Deploy Portfolio Viewer
    portfolioViewer = new SRMPortfolioViewer(subAccounts, cash);

    // Nonce 8: Deploy Standard Manager. Shared by all assets
    srm = new StandardManager(subAccounts, cash, auction, portfolioViewer);
    assertEq(address(srm), address(srmAddr));

    portfolioViewer.setStandardManager(srm);

    // Deploy USDC stable feed
    stableFeed = new MockFeeds();
    stableFeed.setSpot(1e18, 1e18);

    cash.setLiquidationModule(auction);
    cash.setSmFeeRecipient(securityModule.accountId());
    smAcc = securityModule.accountId();

    // todo: allow list
  }

  function _setupCoreContracts() internal {
    // set parameter for auction
    auction.setSolventAuctionParams(_getDefaultAuctionParam());

    auction.setInsolventAuctionParams(_getDefaultInsolventAuctionParam());

    // allow liquidation to request payout from sm
    securityModule.setWhitelistModule(address(auction), true);

    cash.setWhitelistManager(address(srm), true);

    // global setting for SRM
    srm.setStableFeed(stableFeed);
    srm.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.2e18));
  }

  function _deployMarket(string memory key, uint96 initSpotPrice) internal returns (uint8 marketId) {
    marketId = _deployMarketContracts(key);

    // set up PMRM for this market
    _setPMRMParams(markets[key].pmrm, markets[key].pmrmLib);
    // whitelist PMRM to control all assets
    _setupAssetCapsForManager(key, markets[key].pmrm, 1000e18);

    // setup asset configs for standard manager
    _registerMarketToSRM(key);
    // whitelist standard manager to control these assets
    _setupAssetCapsForManager(key, srm, 1000e18);

    cash.setWhitelistManager(address(markets[key].pmrm), true);

    // setup feeds
    _setSignerForFeeds(key, keeper);

    _setSpotPrice(key, initSpotPrice, 1e18);
  }

  function _deployMarketContracts(string memory token) internal returns (uint8 marketId) {
    Market storage market = markets[token];
    marketId = nextId++;
    market.id = marketId;

    MockERC20 erc20 = new MockERC20(token, token);

    market.spotFeed = new LyraSpotFeed();
    market.forwardFeed = new LyraForwardFeed(market.spotFeed);

    Option option = new Option(subAccounts, address(market.forwardFeed));

    PerpAsset perp = new PerpAsset(subAccounts, 0.0075e18);

    WrappedERC20Asset base = new WrappedERC20Asset(subAccounts, erc20);

    // set assets
    market.erc20 = erc20;
    market.option = option;
    market.perp = perp;
    market.base = base;

    // feeds for perp
    market.perpFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.iapFeed = new LyraSpotDiffFeed(market.spotFeed);
    market.ibpFeed = new LyraSpotDiffFeed(market.spotFeed);

    // interest and vol feed
    market.rateFeed = new LyraRateFeed();
    market.volFeed = new LyraVolFeed();

    market.spotFeed.setHeartbeat(1 minutes);
    market.perpFeed.setHeartbeat(20 minutes);
    market.iapFeed.setHeartbeat(20 minutes);
    market.ibpFeed.setHeartbeat(20 minutes);
    market.volFeed.setHeartbeat(20 minutes);
    market.rateFeed.setHeartbeat(24 hours);
    market.forwardFeed.setHeartbeat(20 minutes);
    market.forwardFeed.setSettlementHeartbeat(60 minutes);

    market.pricing = new OptionPricing();

    IPMRM.Feeds memory feeds = IPMRM.Feeds({
      spotFeed: market.spotFeed,
      stableFeed: stableFeed,
      forwardFeed: market.forwardFeed,
      interestRateFeed: market.rateFeed,
      volFeed: market.volFeed,
      settlementFeed: market.forwardFeed
    });

    market.pmrmViewer = new BasePortfolioViewer(subAccounts, cash);
    market.pmrmLib = new PMRMLib(market.pricing);

    market.pmrm = new PMRM(
      subAccounts, 
      cash, 
      option, 
      perp, 
      base, 
      auction,
      feeds,
      market.pmrmViewer,
      market.pmrmLib
    );

    perp.setSpotFeed(market.spotFeed);
    perp.setPerpFeed(market.perpFeed);
    perp.setImpactFeeds(market.iapFeed, market.ibpFeed);
  }

  function _setupAssetCapsForManager(string memory key, IBaseManager manager, uint cap) internal {
    Market storage market = markets[key];

    market.option.setWhitelistManager(address(manager), true);
    market.base.setWhitelistManager(address(manager), true);
    market.perp.setWhitelistManager(address(manager), true);

    // set caps
    market.option.setTotalPositionCap(manager, cap);
    market.perp.setTotalPositionCap(manager, cap);
    market.base.setTotalPositionCap(manager, cap);
  }

  function _setSignerForFeeds(string memory key, address signer) internal {
    markets[key].spotFeed.addSigner(signer, true);
    markets[key].perpFeed.addSigner(signer, true);
    markets[key].iapFeed.addSigner(signer, true);
    markets[key].ibpFeed.addSigner(signer, true);
    markets[key].volFeed.addSigner(signer, true);
    markets[key].rateFeed.addSigner(signer, true);
    markets[key].forwardFeed.addSigner(signer, true);
  }

  function _registerMarketToSRM(string memory key) internal {
    Market storage market = markets[key];

    srm.setPricingModule(market.id, market.pricing);

    // set assets per market
    srm.whitelistAsset(market.perp, market.id, IStandardManager.AssetType.Perpetual);
    srm.whitelistAsset(market.option, market.id, IStandardManager.AssetType.Option);
    srm.whitelistAsset(market.base, market.id, IStandardManager.AssetType.Base);

    // set oracles
    srm.setOraclesForMarket(market.id, market.spotFeed, market.forwardFeed, market.volFeed);

    // set params
    IStandardManager.OptionMarginParams memory params = IStandardManager.OptionMarginParams({
      maxSpotReq: 0.15e18,
      minSpotReq: 0.1e18,
      mmCallSpotReq: 0.075e18,
      mmPutSpotReq: 0.075e18,
      MMPutMtMReq: 0.075e18,
      unpairedIMScale: 1.2e18,
      unpairedMMScale: 1.1e18,
      mmOffsetScale: 1.05e18
    });
    srm.setOptionMarginParams(market.id, params);

    srm.setOracleContingencyParams(market.id, IStandardManager.OracleContingencyParams(0.4e18, 0.4e18, 0.4e18, 0.4e18));

    srm.setPerpMarginRequirements(market.id, 0.05e18, 0.065e18);
  }

  /**
   * @dev helper to mint USDC and deposit cash for account (from user)
   */
  function _depositCash(address user, uint acc, uint amountCash) internal {
    uint amountUSDC = amountCash / 1e12;
    usdc.mint(user, amountUSDC);

    vm.startPrank(user);
    usdc.approve(address(cash), type(uint).max);
    cash.deposit(acc, amountUSDC);
    vm.stopPrank();
  }

  /**
   * @dev helper to mint USDC and deposit cash for account (from user)
   */
  function _depositBase(string memory key, address user, uint acc, uint amount) internal {
    markets[key].erc20.mint(user, amount);

    vm.startPrank(user);
    markets[key].erc20.approve(address(markets[key].base), type(uint).max);
    markets[key].base.deposit(acc, amount);
    vm.stopPrank();
  }

  /**
   * @dev helper to withdraw (or borrow) cash for account (from user)
   */
  function _withdrawCash(address user, uint acc, uint amountCash) internal {
    uint amountUSDC = amountCash / 1e12;
    vm.startPrank(user);
    cash.withdraw(acc, amountUSDC, user);
    vm.stopPrank();
  }

  function _submitTrade(
    uint accA,
    IAsset assetA,
    uint96 subIdA,
    int amountA,
    uint accB,
    IAsset assetB,
    uint subIdB,
    int amountB
  ) internal {
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);

    // accA transfer asset A to accB
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: accA,
      toAcc: accB,
      asset: assetA,
      subId: subIdA,
      amount: amountA,
      assetData: bytes32(0)
    });

    // accB transfer asset B to accA
    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: accB,
      toAcc: accA,
      asset: assetB,
      subId: subIdB,
      amount: amountB,
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");
  }

  function _assertCashSolvent() internal {
    // exchange rate should be >= 1
    assertGe(cash.getCashToStableExchangeRate(), 1e18);
  }

  /**
   * @dev view function to help writing integration test
   */
  function getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }

  /**
   * @dev view function to help writing integration test
   */
  function getOptionBalance(IOption option, uint acc, uint96 subId) public view returns (int) {
    return subAccounts.getBalance(acc, option, subId);
  }

  function getAccInitMargin(uint acc) public view returns (int) {
    return srm.getMargin(acc, true);
  }

  function getAccMaintenanceMargin(uint acc) public view returns (int) {
    return srm.getMargin(acc, false);
  }

  /**
   * @dev default parameters for rate model
   */
  function _getDefaultRateModelParam()
    internal
    pure
    returns (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil)
  {
    minRate = 0.06 * 1e18;
    rateMultiplier = 0.2 * 1e18;
    highRateMultiplier = 0.4 * 1e18;
    optimalUtil = 0.6 * 1e18;
  }

  function _getDefaultAuctionParam() internal pure returns (IDutchAuction.SolventAuctionParams memory param) {
    param = IDutchAuction.SolventAuctionParams({
      startingMtMPercentage: 1e18,
      fastAuctionCutoffPercentage: 0.8e18,
      fastAuctionLength: 10 minutes,
      slowAuctionLength: 2 hours,
      liquidatorFeeRate: 0.05e18
    });
  }

  function _getDefaultInsolventAuctionParam() internal pure returns (IDutchAuction.InsolventAuctionParams memory param) {
    param = IDutchAuction.InsolventAuctionParams({totalSteps: 100, coolDown: 5 seconds, bufferMarginScalar: 1.2e18});
  }

  function getSubId(uint expiry, uint strike, bool isCall) public pure returns (uint96) {
    return OptionEncoding.toSubId(expiry, strike, isCall);
  }

  ////////////////////////////////////
  //     Feed setting functions     //
  ////////////////////////////////////

  function _getSpot(string memory key) internal view returns (uint, uint) {
    LyraSpotFeed spotFeed = markets[key].spotFeed;
    return spotFeed.getSpot();
  }

  function _setSpotPrice(string memory key, uint96 price, uint64 conf) internal {
    LyraSpotFeed spotFeed = markets[key].spotFeed;
    bytes memory data = abi.encode(price, conf);
    IBaseLyraFeed.FeedData memory feedData = IBaseLyraFeed.FeedData({
      data: data,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });

    // sign data
    bytes memory managerData = _signFeedData(spotFeed, keeperPk, feedData);

    // submit to feed
    spotFeed.acceptData(managerData);
  }

  /**
   * @dev set current price of aggregator, and report as settlement price at {expiry}
   * @param price price in 18 decimals
   */
  function _setSettlementPrice(string memory key, uint64 expiry, uint price) internal {
    LyraForwardFeed feed = markets[key].forwardFeed;

    (uint spot,) = markets[key].spotFeed.getSpot();

    int96 diff = int96(int(price) - int(spot));

    uint startAggregate = price * uint(expiry - feed.SETTLEMENT_TWAP_DURATION());
    uint currAggregate = price * uint(expiry);

    IBaseLyraFeed.FeedData memory feedData = IBaseLyraFeed.FeedData({
      data: abi.encode(expiry, startAggregate, currAggregate, diff, 1e18),
      timestamp: uint64(expiry), // timestamp need to be expiry to be used as settlement data
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });

    feed.acceptData(_signFeedData(feed, keeperPk, feedData));
  }

  function _getForwardPrice(string memory key, uint expiry) internal view returns (uint, uint) {
    LyraForwardFeed forwardFeed = markets[key].forwardFeed;
    return forwardFeed.getForwardPrice(uint64(expiry));
  }

  /**
   * @dev set current price of aggregator, and report as settlement price at {expiry}
   * @param price price in 18 decimals
   */
  function _setForwardPrice(string memory key, uint64 expiry, uint price, uint64 conf) internal {
    LyraForwardFeed feed = markets[key].forwardFeed;

    (uint spot,) = markets[key].spotFeed.getSpot();

    int96 diff = int96(int(price) - int(spot));

    IBaseLyraFeed.FeedData memory feedData = IBaseLyraFeed.FeedData({
      data: abi.encode(expiry, 0, 0, diff, conf),
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });

    feed.acceptData(_signFeedData(feed, keeperPk, feedData));
  }

  function _getPerpPrice(string memory key) internal view returns (uint, uint) {
    LyraSpotDiffFeed perpFeed = markets[key].perpFeed;
    return perpFeed.getResult();
  }

  function _setPerpPrice(string memory key, uint price, uint64 conf) internal {
    vm.warp(block.timestamp + 5);
    LyraSpotDiffFeed perpFeed = markets[key].perpFeed;

    (uint spot,) = markets[key].spotFeed.getSpot();

    int96 diff = int96(int(price) - int(spot));

    IBaseLyraFeed.FeedData memory feedData = IBaseLyraFeed.FeedData({
      data: abi.encode(diff, conf),
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });

    bytes memory data = _signFeedData(perpFeed, keeperPk, feedData);

    perpFeed.acceptData(data);
  }

  function _setDefaultSVIForExpiry(string memory key, uint64 expiry) internal {
    vm.warp(block.timestamp + 5);

    LyraForwardFeed forwardFeed = markets[key].forwardFeed;
    (uint fwdPrice,) = forwardFeed.getForwardPrice(uint64(expiry));

    LyraVolFeed volFeed = markets[key].volFeed;

    IBaseLyraFeed.FeedData memory feedData = _getDefaultVolData(expiry, fwdPrice);

    // sign data
    bytes memory data = _signFeedData(volFeed, keeperPk, feedData);

    volFeed.acceptData(data);
  }

  function _getInterestRate(string memory key, uint64 expiry) internal view returns (int, uint) {
    LyraRateFeed rateFeed = markets[key].rateFeed;
    return rateFeed.getInterestRate(expiry);
  }

  function _setInterestRate(string memory key, uint64 expiry, int96 rate, uint64 conf) internal {
    LyraRateFeed rateFeed = markets[key].rateFeed;
    bytes memory rateData = abi.encode(expiry, rate, conf);
    IBaseLyraFeed.FeedData memory feedData = IBaseLyraFeed.FeedData({
      data: rateData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });

    // sign data
    bytes memory data = _signFeedData(rateFeed, keeperPk, feedData);

    rateFeed.acceptData(data);
  }

  function _signFeedData(IBaseLyraFeed feed, uint privateKey, IBaseLyraFeed.FeedData memory feedData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 structHash = hashFeedData(feed, feedData);
    bytes32 domainSeparator = feed.domainSeparator();
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    feedData.signatures[0] = bytes.concat(r, s, bytes1(v));
    feedData.signers[0] = vm.addr(privateKey);

    return abi.encode(feedData);
  }

  function hashFeedData(IBaseLyraFeed feed, IBaseLyraFeed.FeedData memory feedData) public view returns (bytes32) {
    bytes32 typeHash = feed.FEED_DATA_TYPEHASH();
    return keccak256(abi.encode(typeHash, feedData.data, feedData.deadline, feedData.timestamp));
  }

  function _setPMRMParams(PMRM pmrm, PMRMLib pmrmLib) internal {
    (
      IPMRMLib.BasisContingencyParameters memory basisContParams,
      IPMRMLib.OtherContingencyParameters memory otherContParams,
      IPMRMLib.MarginParameters memory marginParams,
      IPMRMLib.VolShockParameters memory volShockParams
    ) = getPMRMParams();

    pmrmLib.setBasisContingencyParams(basisContParams);
    pmrmLib.setOtherContingencyParams(otherContParams);
    pmrmLib.setMarginParams(marginParams);
    pmrmLib.setVolShockParams(volShockParams);

    // _addScenarios(pmrm);
    pmrm.setScenarios(getDefaultScenarios());
  }

  function _getDefaultVolData(uint64 expiry, uint fwdPrice) internal view returns (IBaseLyraFeed.FeedData memory) {
    int SVI_a = 1e18;
    uint SVI_b = 1.5e18;
    int SVI_rho = -0.1e18;
    int SVI_m = -0.05e18;
    uint SVI_sigma = 0.05e18;
    uint SVI_fwd = fwdPrice;
    uint64 SVI_refTao = uint64(Black76.annualise(uint64(expiry - block.timestamp)));
    uint64 confidence = 1e18;

    // example data: a = 1, b = 1.5, sig = 0.05, rho = -0.1, m = -0.05
    bytes memory volData = abi.encode(expiry, SVI_a, SVI_b, SVI_rho, SVI_m, SVI_sigma, SVI_fwd, SVI_refTao, confidence);
    return IBaseLyraFeed.FeedData({
      data: volData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
  }

  ////////////////
  //    Misc    //
  ////////////////

  /**
   * @dev predict the address of the next contract being deployed
   */
  function _predictAddress(address _origin, uint _nonce) public pure returns (address) {
    if (_nonce == 0x00) {
      return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80))))));
    }
    if (_nonce <= 0x7f) {
      return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce))))));
    }
    if (_nonce <= 0xff) {
      return address(
        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce)))))
      );
    }
    if (_nonce <= 0xffff) {
      return address(
        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce)))))
      );
    }
    if (_nonce <= 0xffffff) {
      return address(
        uint160(uint(keccak256(abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce)))))
      );
    }
    return address(
      uint160(uint(keccak256(abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce)))))
    );
  }
}
