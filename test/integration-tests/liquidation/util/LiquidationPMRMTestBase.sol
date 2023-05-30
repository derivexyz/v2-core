pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import "src/assets/CashAsset.sol";
import "src/SubAccounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/ISubAccounts.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/shared/mocks/MockFeeds.sol";
import "test/auction/mocks/MockCashAsset.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";
import "test/shared/utils/JsonMechIO.sol";

import "forge-std/console2.sol";
import "../../../shared/mocks/MockFeeds.sol";
import "../../../../src/assets/WrappedERC20Asset.sol";
import "../../../shared/mocks/MockPerp.sol";
import "../../../../src/feeds/OptionPricing.sol";
import "test/risk-managers/unit-tests/PMRM/PMRMPublic.sol";
import "./LiquidationSimLoading.sol";
import "../../../../src/liquidation/DutchAuction.sol";

contract LiquidationPMRMTestBase is LiquidationSimLoading, Test {
  using stdJson for string;

  SubAccounts subAccounts;
  PMRMPublic pmrm;
  MockCash cash;
  MockERC20 usdc;
  MockERC20 weth;
  WrappedERC20Asset baseAsset;

  JsonMechIO jsonParser;

  MockOption option;
  DutchAuction auction;
  MockSM sm;
  MockFeeds feed;
  MockFeeds perpFeed;
  MockFeeds stableFeed;
  uint feeRecipient;
  OptionPricing optionPricing;
  MockPerp mockPerp;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public virtual {
    vm.warp(1640995200); // 1st jan 2022

    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    feed = new MockFeeds();
    perpFeed = new MockFeeds();
    stableFeed = new MockFeeds();
    feed.setSpot(1500e18, 1e18);
    stableFeed.setSpot(1e18, 1e18);
    perpFeed.setSpot(1500e18, 1e18);

    usdc = new MockERC20("USDC", "USDC");
    weth = new MockERC20("weth", "weth");
    cash = new MockCash(usdc, subAccounts);
    baseAsset = new WrappedERC20Asset(subAccounts, weth);
    mockPerp = new MockPerp(subAccounts);

    option = new MockOption(subAccounts);
    optionPricing = new OptionPricing();

    sm = new MockSM(subAccounts, cash);
    auction = new DutchAuction(subAccounts, sm, cash);

    pmrm = new PMRMPublic(
      subAccounts,
      cash,
      option,
      mockPerp,
      IOptionPricing(optionPricing),
      baseAsset,
      auction,
      IPMRM.Feeds({
        spotFeed: ISpotFeed(feed),
        perpFeed: ISpotFeed(perpFeed),
        stableFeed: ISpotFeed(stableFeed),
        forwardFeed: IForwardFeed(feed),
        interestRateFeed: IInterestRateFeed(feed),
        volFeed: IVolFeed(feed),
        settlementFeed: ISettlementFeed(feed)
      })
    );

    baseAsset.setWhitelistManager(address(pmrm), true);

    _setupAliceAndBob();
    addScenarios();

    feeRecipient = subAccounts.createAccount(address(this), pmrm);
    pmrm.setFeeRecipient(feeRecipient);

    auction.setSolventAuctionParams(_getDefaultSolventParams());
    auction.setInsolventAuctionParams(_getDefaultInsolventParams());
    auction.setBufferMarginPercentage(0.2e18);

    sm.createAccountForSM(pmrm);
  }

  function _logPortfolio(IPMRM.Portfolio memory portfolio) internal view {
    console2.log("cash balance:", portfolio.cash);
    console2.log("\nOTHER ASSETS");
    console2.log("TODO");
    //    console2.log("count:", uint(portfolio.otherAssets.length));
    //    for (uint i = 0; i < portfolio.otherAssets.length; i++) {
    //      console2.log("- asset:", portfolio.otherAssets[i].asset);
    //      console2.log("- balance:", portfolio.otherAssets[i].amount);
    //      console2.log("----");
    //    }

    console2.log("spotPrice", portfolio.spotPrice);
    console2.log("stablePrice", portfolio.stablePrice);
    console2.log("cash", portfolio.cash);
    console2.log("perpPosition", portfolio.perpPosition);
    console2.log("basePosition", portfolio.basePosition);
    console2.log("baseValue", portfolio.baseValue);
    console2.log("totalMtM", portfolio.totalMtM);
    console2.log("fwdContingency", portfolio.fwdContingency);
    console2.log("staticContingency", portfolio.staticContingency);
    console2.log("confidenceContingency", portfolio.confidenceContingency);

    console2.log("\n");
    console2.log("expiryLen", uint(portfolio.expiries.length));
    console2.log("==========");
    console2.log();
    for (uint i = 0; i < portfolio.expiries.length; i++) {
      PMRM.ExpiryHoldings memory expiry = portfolio.expiries[i];
      console2.log("=== secToExpiry:", expiry.secToExpiry);
      console2.log("params:");

      console2.log("forwardFixedPortion", expiry.forwardFixedPortion);
      console2.log("forwardVariablePortion", expiry.forwardVariablePortion);
      console2.log("volShockUp", expiry.volShockUp);
      console2.log("volShockDown", expiry.volShockDown);
      console2.log("mtm", expiry.mtm);
      console2.log("fwdShock1MtM", expiry.fwdShock1MtM);
      console2.log("fwdShock2MtM", expiry.fwdShock2MtM);
      console2.log("staticDiscount", expiry.staticDiscount);
      console2.log("minConfidence", expiry.minConfidence);

      for (uint j = 0; j < expiry.options.length; j++) {
        console2.log(expiry.options[j].isCall ? "- CALL" : "- PUT");
        console2.log("- strike:", expiry.options[j].strike / 1e18);
        console2.log("- amount:", expiry.options[j].amount / 1e18);
      }
    }
  }

  function addScenarios() internal {
    // Scenario Number	Spot Shock (of max)	Vol Shock (of max)

    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](21);

    // add these 27 scenarios to the array
    scenarios[0] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.Up});
    scenarios[1] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.None});
    scenarios[2] = IPMRM.Scenario({spotShock: 1.15e18, volShock: IPMRM.VolShockDirection.Down});
    scenarios[3] = IPMRM.Scenario({spotShock: 1.1e18, volShock: IPMRM.VolShockDirection.Up});
    scenarios[4] = IPMRM.Scenario({spotShock: 1.1e18, volShock: IPMRM.VolShockDirection.None});
    scenarios[5] = IPMRM.Scenario({spotShock: 1.1e18, volShock: IPMRM.VolShockDirection.Down});
    scenarios[6] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.Up});
    scenarios[7] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.None});
    scenarios[8] = IPMRM.Scenario({spotShock: 1.05e18, volShock: IPMRM.VolShockDirection.Down});
    scenarios[9] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.Up});
    scenarios[10] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.None});
    scenarios[11] = IPMRM.Scenario({spotShock: 1e18, volShock: IPMRM.VolShockDirection.Down});
    scenarios[12] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.Up});
    scenarios[13] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.None});
    scenarios[14] = IPMRM.Scenario({spotShock: 0.95e18, volShock: IPMRM.VolShockDirection.Down});
    scenarios[15] = IPMRM.Scenario({spotShock: 0.9e18, volShock: IPMRM.VolShockDirection.Up});
    scenarios[16] = IPMRM.Scenario({spotShock: 0.9e18, volShock: IPMRM.VolShockDirection.None});
    scenarios[17] = IPMRM.Scenario({spotShock: 0.9e18, volShock: IPMRM.VolShockDirection.Down});
    scenarios[18] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.Up});
    scenarios[19] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.None});
    scenarios[20] = IPMRM.Scenario({spotShock: 0.85e18, volShock: IPMRM.VolShockDirection.Down});

    pmrm.setScenarios(scenarios);
  }

  function _setupAliceAndBob() internal {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    aliceAcc = subAccounts.createAccount(alice, IManager(address(pmrm)));
    bobAcc = subAccounts.createAccount(bob, IManager(address(pmrm)));

    // allow this contract to submit trades
    vm.prank(alice);
    subAccounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    subAccounts.setApprovalForAll(address(this), true);
  }

  function _depositCash(uint accId, uint amount) internal {
    usdc.mint(address(this), amount);
    usdc.approve(address(cash), amount);
    cash.deposit(accId, amount);
  }

  function _setupAccount(address signer) internal returns (uint accountId) {
    accountId = subAccounts.createAccount(signer, IManager(address(pmrm)));

    // allow this contract to submit trades
    vm.prank(signer);
    subAccounts.setApprovalForAll(address(this), true);
  }

  function setupTestScenarioAndGetAssetBalances(LiquidationSimLoading.LiquidationSim memory data)
    internal
    returns (ISubAccounts.AssetBalance[] memory balances)
  {
    vm.warp(data.StartTime);

    uint totalAssets = data.InitialPortfolio.OptionStrikes.length;

    totalAssets += data.InitialPortfolio.Cash != 0 ? 1 : 0;
    totalAssets += data.InitialPortfolio.PerpPosition != 0 ? 1 : 0;
    totalAssets += data.InitialPortfolio.BasePosition != 0 ? 1 : 0;

    balances = new ISubAccounts.AssetBalance[](totalAssets);

    uint i = 0;
    for (; i < data.InitialPortfolio.OptionStrikes.length; ++i) {
      balances[i] = ISubAccounts.AssetBalance({
        asset: IAsset(option),
        subId: OptionEncoding.toSubId(
          data.InitialPortfolio.OptionExpiry[i],
          data.InitialPortfolio.OptionStrikes[i],
          data.InitialPortfolio.OptionIsCall[i]
          ),
        balance: data.InitialPortfolio.OptionAmount[i]
      });
    }

    if (data.InitialPortfolio.Cash != 0) {
      balances[i++] =
        ISubAccounts.AssetBalance({asset: IAsset(address(cash)), subId: 0, balance: data.InitialPortfolio.Cash});
    }
    if (data.InitialPortfolio.PerpPosition != 0) {
      balances[i++] = ISubAccounts.AssetBalance({
        asset: IAsset(address(mockPerp)),
        subId: 0,
        balance: data.InitialPortfolio.PerpPosition
      });
    }
    if (data.InitialPortfolio.BasePosition != 0) {
      balances[i++] = ISubAccounts.AssetBalance({
        asset: IAsset(address(baseAsset)),
        subId: 0,
        balance: data.InitialPortfolio.BasePosition
      });
    }

    return balances;
  }

  function setBalances(uint acc, ISubAccounts.AssetBalance[] memory balances) internal {
    pmrm.setBalances(acc, balances);
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }

  function _getDefaultSolventParams() internal pure returns (IDutchAuction.SolventAuctionParams memory) {
    return IDutchAuction.SolventAuctionParams({
      startingMtMPercentage: 0.98e18,
      fastAuctionCutoffPercentage: 0.8e18,
      fastAuctionLength: 100,
      slowAuctionLength: 7200,
      liquidatorFeeRate: 0.02e18
    });
  }

  function _getDefaultInsolventParams() internal pure returns (IDutchAuction.InsolventAuctionParams memory) {
    return IDutchAuction.InsolventAuctionParams({totalSteps: 100, coolDown: 5, bufferMarginScalar: 1.2e18});
  }
}
