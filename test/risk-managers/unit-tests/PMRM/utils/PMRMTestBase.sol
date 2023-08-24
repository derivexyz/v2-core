pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {IAsset} from "../../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../../src/interfaces/ISubAccounts.sol";
import {IManager} from "../../../../../src/interfaces/IManager.sol";
import {IDutchAuction} from "../../../../../src/interfaces/IDutchAuction.sol";
import {IOptionPricing} from "../../../../../src/interfaces/IOptionPricing.sol";
import {ISpotFeed} from "../../../../../src/interfaces/ISpotFeed.sol";
import {IForwardFeed} from "../../../../../src/interfaces/IForwardFeed.sol";
import {IInterestRateFeed} from "../../../../../src/interfaces/IInterestRateFeed.sol";
import {IVolFeed} from "../../../../../src/interfaces/IVolFeed.sol";
import {ISettlementFeed} from "../../../../../src/interfaces/ISettlementFeed.sol";
import {IPMRM} from "../../../../../src/interfaces/IPMRM.sol";

import {SubAccounts} from "../../../../../src/SubAccounts.sol";
import {CashAsset} from "../../../../../src/assets/CashAsset.sol";
import {WrappedERC20Asset} from "../../../../../src/assets/WrappedERC20Asset.sol";
import {OptionPricing} from "../../../../../src/feeds/OptionPricing.sol";
import {PMRM} from "../../../../../src/risk-managers/PMRM.sol";
import {PMRMLib} from "../../../../../src/risk-managers/PMRMLib.sol";
import {BasePortfolioViewer} from "../../../../../src/risk-managers/BasePortfolioViewer.sol";
import {DutchAuction} from "../../../../../src/liquidation/DutchAuction.sol";

import {MockManager} from "../../../../shared/mocks/MockManager.sol";
import {MockERC20} from "../../../../shared/mocks/MockERC20.sol";
import {MockAsset} from "../../../../shared/mocks/MockAsset.sol";
import {MockOption} from "../../../../shared/mocks/MockOptionAsset.sol";
import {MockSM} from "../../../../shared/mocks/MockSM.sol";
import {MockFeeds} from "../../../../shared/mocks/MockFeeds.sol";
import {MockFeeds} from "../../../../shared/mocks/MockFeeds.sol";
import {MockPerp} from "../../../../shared/mocks/MockPerp.sol";
import {MockSpotDiffFeed} from "../../../../shared/mocks/MockSpotDiffFeed.sol";
import {MockCash} from "../../../../auction/mocks/MockCashAsset.sol";
import {MockDutchAuction} from "../../../../risk-managers/mocks/MockDutchAuction.sol";
import {PMRMPublic} from "../../../../risk-managers/unit-tests/PMRM/utils/PMRMPublic.sol";

import {IPMRMLib} from "../../../../../src/interfaces/IPMRMLib.sol";

import "../../../../shared/utils/JsonMechIO.sol";

contract PMRMTestBase is JsonMechIO {
  using stdJson for string;

  SubAccounts subAccounts;
  PMRMPublic pmrm;
  MockCash cash;
  MockERC20 usdc;
  MockERC20 weth;
  WrappedERC20Asset baseAsset;

  MockOption option;
  DutchAuction auction;
  MockSM sm;
  MockFeeds feed;
  MockSpotDiffFeed perpFeed;
  MockFeeds stableFeed;
  uint feeRecipient;
  OptionPricing optionPricing;
  MockPerp mockPerp;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  BasePortfolioViewer viewer;
  PMRMLib lib;

  function setUp() public virtual {
    vm.warp(1640995200); // 1st jan 2022

    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    feed = new MockFeeds();
    perpFeed = new MockSpotDiffFeed(feed);
    stableFeed = new MockFeeds();
    feed.setSpot(1500e18, 1e18);
    stableFeed.setSpot(1e18, 1e18);

    usdc = new MockERC20("USDC", "USDC");
    weth = new MockERC20("weth", "weth");
    cash = new MockCash(usdc, subAccounts);
    baseAsset = new WrappedERC20Asset(subAccounts, weth);
    mockPerp = new MockPerp(subAccounts);

    option = new MockOption(subAccounts);
    optionPricing = new OptionPricing();

    sm = new MockSM(subAccounts, cash);
    auction = new DutchAuction(subAccounts, sm, cash);

    viewer = new BasePortfolioViewer(subAccounts, cash);
    lib = new PMRMLib(optionPricing);

    pmrm = new PMRMPublic(
      subAccounts,
      cash,
      option,
      mockPerp,
      baseAsset,
      auction,
      IPMRM.Feeds({
        spotFeed: ISpotFeed(feed),
        stableFeed: ISpotFeed(stableFeed),
        forwardFeed: IForwardFeed(feed),
        interestRateFeed: IInterestRateFeed(feed),
        volFeed: IVolFeed(feed),
        settlementFeed: ISettlementFeed(feed)
      }),
      viewer,
      lib
    );
    setDefaultParameters();
    addScenarios();

    baseAsset.setWhitelistManager(address(pmrm), true);
    baseAsset.setTotalPositionCap(pmrm, 100e18);

    _setupAliceAndBob();

    feeRecipient = subAccounts.createAccount(address(this), pmrm);
    pmrm.setFeeRecipient(feeRecipient);

    auction.setSolventAuctionParams(_getDefaultSolventParams());
    auction.setInsolventAuctionParams(_getDefaultInsolventParams());
    auction.setBufferMarginPercentage(0.2e18);

    sm.createAccountForSM(pmrm);
  }

  function setDefaultParameters() internal {
    IPMRMLib.BasisContingencyParameters memory basisContParams = IPMRMLib.BasisContingencyParameters({
      scenarioSpotUp: 1.05e18,
      scenarioSpotDown: 0.95e18,
      basisContAddFactor: 0.25e18,
      basisContMultFactor: 0.01e18
    });

    IPMRMLib.OtherContingencyParameters memory otherContParams = IPMRMLib.OtherContingencyParameters({
      pegLossThreshold: 0.98e18,
      pegLossFactor: 2e18,
      confThreshold: 0.6e18,
      confMargin: 0.5e18,
      basePercent: 0.02e18,
      perpPercent: 0.02e18,
      optionPercent: 0.01e18
    });

    IPMRMLib.MarginParameters memory marginParams = IPMRMLib.MarginParameters({
      imFactor: 1.3e18,
      baseStaticDiscount: 0.95e18,
      rateMultScale: 4e18,
      rateAddScale: 0.05e18
    });

    IPMRMLib.VolShockParameters memory volShockParams = IPMRMLib.VolShockParameters({
      volRangeUp: 0.45e18,
      volRangeDown: 0.3e18,
      shortTermPower: 0.3e18,
      longTermPower: 0.13e18,
      dteFloor: 1 days
    });

    lib.setBasisContingencyParams(basisContParams);
    lib.setOtherContingencyParams(otherContParams);
    lib.setMarginParams(marginParams);
    lib.setVolShockParams(volShockParams);
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
    console2.log("basisContingency", portfolio.basisContingency);
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
      console2.log("basisScenarioUpMtM", expiry.basisScenarioUpMtM);
      console2.log("basisScenarioDownMtM", expiry.basisScenarioDownMtM);
      console2.log("staticDiscount", expiry.staticDiscount);
      console2.log("minConfidence", expiry.minConfidence);

      for (uint j = 0; j < expiry.options.length; j++) {
        console2.log(expiry.options[j].isCall ? "- CALL" : "- PUT");
        console2.log("- strike:", expiry.options[j].strike);
        console2.log("- amount:", expiry.options[j].amount);
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

  function setBalances(uint acc, ISubAccounts.AssetBalance[] memory balances) internal {
    pmrm.setBalances(acc, balances);
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

  function _doBalanceTransfer(uint accA, uint accB, ISubAccounts.AssetBalance[] memory balances) internal {
    subAccounts.submitTransfers(_getTransferBatch(accA, accB, balances), "");
  }

  function _getTransferBatch(uint accA, uint accB, ISubAccounts.AssetBalance[] memory balances)
    internal
    pure
    returns (ISubAccounts.AssetTransfer[] memory)
  {
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](balances.length);

    for (uint i = 0; i < balances.length; i++) {
      transferBatch[i] = ISubAccounts.AssetTransfer({
        fromAcc: accA,
        toAcc: accB,
        asset: balances[i].asset,
        subId: balances[i].subId,
        amount: balances[i].balance,
        assetData: bytes32(0)
      });
    }

    return transferBatch;
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return subAccounts.getBalance(acc, cash, 0);
  }

  function _getDefaultSolventParams() internal pure returns (IDutchAuction.SolventAuctionParams memory) {
    return IDutchAuction.SolventAuctionParams({
      startingMtMPercentage: 0.98e18,
      fastAuctionCutoffPercentage: 0.8e18,
      fastAuctionLength: 100,
      slowAuctionLength: 14400,
      liquidatorFeeRate: 0.02e18
    });
  }

  function _getDefaultInsolventParams() internal pure returns (IDutchAuction.InsolventAuctionParams memory) {
    return IDutchAuction.InsolventAuctionParams({totalSteps: 100, coolDown: 0, bufferMarginScalar: 1.1e18});
  }
}
