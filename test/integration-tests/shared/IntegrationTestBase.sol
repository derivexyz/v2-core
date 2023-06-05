// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
//

import "forge-std/Test.sol";

import "src/SecurityModule.sol";
import "src/assets/CashAsset.sol";
import "src/assets/Option.sol";
import "src/assets/PerpAsset.sol";
import "src/assets/InterestRateModel.sol";

import "src/assets/WrappedERC20Asset.sol";

import "src/liquidation/DutchAuction.sol";
import "src/SubAccounts.sol";

import "src/risk-managers/StandardManager.sol";
import "src/risk-managers/PMRM.sol";

import "src/feeds/OptionPricing.sol";

import "../../shared/mocks/MockFeeds.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockSpotDiffFeed.sol";

/**
 * @dev real Accounts contract
 * @dev real CashAsset contract
 * @dev real SecurityModule contract
 */
contract IntegrationTestBase is Test {
  address alice = address(0xace);
  address bob = address(0xb0b);
  uint aliceAcc;
  uint bobAcc;

  address public constant liquidation = address(0xdead);
  uint public constant DEFAULT_DEPOSIT = 5000e18;
  int public constant ETH_PRICE = 2000e18;

  SubAccounts subAccounts;
  MockERC20 usdc;
  MockERC20 weth;

  // Lyra Assets
  CashAsset cash;
  Option ethOption;
  Option btcOption;
  PerpAsset ethPerp;
  PerpAsset btcPerp;
  WrappedERC20Asset ethBase;
  WrappedERC20Asset btcBase;

  OptionPricing ethPricing;

  StandardManager srm;

  SecurityModule securityModule;
  InterestRateModel rateModel;
  DutchAuction auction;
  MockFeeds ethFeed;
  MockFeeds btcFeed;
  MockFeeds stableFeed;

  MockSpotDiffFeed ethPerpFeed;
  MockSpotDiffFeed btcPerpFeed;

  // sm account id will be 1 after setup
  uint smAcc = 1;

  uint8 ethMarketId = 1;
  uint8 btcMarketId = 2;

  function _setupIntegrationTestComplete() internal {
    // deploy Accounts, cash, security module, auction
    _deployAllV2Contracts();

    (weth, ethOption, ethPerp, ethBase, ethFeed, ethPerpFeed, ethPricing) = _deployMarket("weth");

    // setup config on assets
    _setupAssets();

    // setup managers
    _setupStandardManager();

    _setupAuctionAndSM();

    _setupAliceAndBob();
  }

  function _setupAliceAndBob() internal {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    aliceAcc = subAccounts.createAccount(alice, srm);
    bobAcc = subAccounts.createAccount(bob, srm);

    // allow this contract to submit trades
    vm.prank(alice);
    subAccounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    subAccounts.setApprovalForAll(address(this), true);
  }

  function _deployAllV2Contracts() internal {
    // nonce: 1 => Deploy Accounts
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    // nonce: 2 => Deploy USDC
    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    // nonce: 3 => Deploy RateModel
    // deploy rate model
    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = _getDefaultRateModelParam();
    rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    // nonce: 4 => Deploy CashAsset
    address auctionAddr = _predictAddress(address(this), 7);
    cash = new CashAsset(subAccounts, usdc, rateModel, smAcc, auctionAddr);

    // nonce: 5 => Deploy Manager
    srm = new StandardManager(subAccounts, cash, IDutchAuction(auctionAddr));

    // nonce: 6 => Deploy SM
    securityModule = new SecurityModule(subAccounts, cash, srm);

    // nonce: 7 => Deploy Auction
    auction = new DutchAuction(subAccounts, securityModule, cash);

    assertEq(address(auction), auctionAddr);

    // nonce: 8 => USDC stable feed
    stableFeed = new MockFeeds();
    stableFeed.setSpot(1e18, 1e18);

    // todo: allow list
  }

  function _deployMarket(string memory token)
    internal
    returns (
      MockERC20 erc20,
      Option option,
      PerpAsset perp,
      WrappedERC20Asset base,
      MockFeeds feed,
      MockSpotDiffFeed perpFeed,
      OptionPricing pricing
    )
  {
    erc20 = new MockERC20(token, token);

    feed = new MockFeeds();

    option = new Option(subAccounts, address(feed));

    perp = new PerpAsset(subAccounts, 0.0075e18);

    base = new WrappedERC20Asset(subAccounts, erc20);

    perpFeed = new MockSpotDiffFeed(feed);

    pricing = new OptionPricing();
  }

  function _setupAssets() internal {
    // whitelist setting in cash asset and option assert
    cash.setWhitelistManager(address(srm), true);
    ethOption.setWhitelistManager(address(srm), true);
    ethBase.setWhitelistManager(address(srm), true);
    ethPerp.setWhitelistManager(address(srm), true);

    // set caps
    ethOption.setTotalPositionCap(srm, 10000e18);
    ethPerp.setTotalPositionCap(srm, 10000e18);
    ethBase.setTotalPositionCap(srm, 10000e18);

    ethPerp.setSpotFeed(ethFeed);
    ethPerp.setPerpFeed(ethPerpFeed);

    ethFeed.setSpot(2000e18, 1e18);
  }

  function _setupStandardManager() internal {
    srm.setStableFeed(stableFeed);

    srm.setPricingModule(ethMarketId, ethPricing);

    // set assets per market
    srm.whitelistAsset(ethPerp, ethMarketId, IStandardManager.AssetType.Perpetual);
    srm.whitelistAsset(ethOption, ethMarketId, IStandardManager.AssetType.Option);
    srm.whitelistAsset(ethBase, ethMarketId, IStandardManager.AssetType.Base);

    // set oracles
    srm.setOraclesForMarket(ethMarketId, ethFeed, ethFeed, ethFeed, ethFeed);

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
    srm.setOptionMarginParams(ethMarketId, params);

    srm.setOracleContingencyParams(
      ethMarketId, IStandardManager.OracleContingencyParams(0.4e18, 0.4e18, 0.4e18, 0.4e18)
    );
    srm.setDepegParameters(IStandardManager.DepegParams(0.98e18, 1.2e18));

    srm.setPerpMarginRequirements(ethMarketId, 0.05e18, 0.065e18);
  }

  function _setupAuctionAndSM() internal {
    // set parameter for auction
    auction.setSolventAuctionParams(_getDefaultAuctionParam());

    // allow liquidation to request payout from sm
    securityModule.setWhitelistModule(address(auction), true);
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

  /**
   * @dev set current price of aggregator, and report as settlement price at {expiry}
   * @param price price in 18 decimals
   */
  function _setSettlementPrice(MockFeeds feed, int price, uint expiry) internal {
    // todo: update to use signature
    feed.setSettlementPrice(expiry, uint(price));
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

  function _getForwardPrice(IForwardFeed feed, uint expiry) internal view returns (uint forwardPrice) {
    (forwardPrice,) = feed.getForwardPrice(uint64(expiry));
    return forwardPrice;
  }

  /**
   * for coverage to ignore
   */
  function test() public {}
}
