// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/PMRM_2.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";

import "../../../risk-managers/unit-tests/PMRM_2/utils/PMRM_2SimTest.sol";

contract UNIT_TestPMRM_2_EdgeCases is PMRM_2SimTest {
  function testPMRM_2_perpTransfer() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");

    _depositCash(aliceAcc, 2_000 ether);
    _depositCash(bobAcc, 2_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_2_unsupportedAsset() public {
    MockOption newAsset = new MockOption(subAccounts);
    // newAsset.setWhitelistManager(address(PMRM_2), true);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(address(newAsset)), balance: 1_000 ether, subId: 0});
    vm.expectRevert(IPMRM_2.PMRM_2_UnsupportedAsset.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }
  //  // TODO: we have no caps because of dampening, maybe we want one?
  //  function testPMRM_2_invalidSpotShock() public {
  //    IPMRM_2.Scenario[] memory scenarios = new IPMRM_2.Scenario[](1);
  //    scenarios[0] =
  //      IPMRM_2.Scenario({spotShock: 3e18 + 1, volShock: IPMRM_2.VolShockDirection.None, dampeningFactor: 1e18});
  //
  //    vm.expectRevert(IPMRM_2.PMRM_2_InvalidSpotShock.selector);
  //    pmrm_2.setScenarios(scenarios);
  //
  //    // but this works fine
  //    scenarios[0].spotShock = 3e18;
  //    pmrm_2.setScenarios(scenarios);
  //  }

  function testPMRM_2_notFoundError() public {
    IPMRM_2.ExpiryHoldings[] memory expiryData = new IPMRM_2.ExpiryHoldings[](0);
    vm.expectRevert(IPMRM_2.PMRM_2_FindInArrayError.selector);
    pmrm_2.findInArrayPub(expiryData, 0, 0);
  }

  function testPMRM_2_noScenarios() public {
    // Cannot set no scenarios
    vm.expectRevert(IPMRM_2.PMRM_2_InvalidScenarios.selector);
    pmrm_2.setScenarios(new IPMRM_2.Scenario[](0));
  }

  function testPMRM_2_invalidGetMarginState() public {
    IPMRM_2.Scenario[] memory scenarios = new IPMRM_2.Scenario[](0);

    IPMRM_2.Portfolio memory portfolio;
    vm.expectRevert(IPMRMLib_2.PMRM_2L_InvalidGetMarginState.selector);
    pmrm_2.getMarginAndMarkToMarketPub(portfolio, true, scenarios);

    vm.expectRevert(IPMRMLib_2.PMRM_2L_InvalidGetMarginState.selector);
    pmrm_2.getMarginAndMarkToMarketPub(portfolio, true, scenarios);
  }

  function testPMRM_2_CannotTradeIfExceed_MaxAssets() public {
    uint expiry = block.timestamp + 1000;
    pmrm_2.setMaxAccountSize(10);
    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](pmrm_2.maxAccountSize() + 1);
    for (uint i = 0; i < transfers.length; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: option,
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        amount: 1e18,
        assetData: ""
      });
    }
    vm.expectRevert(IPMRM_2.PMRM_2_TooManyAssets.selector);
    subAccounts.submitTransfers(transfers, "");
  }

  function testPMRM_2_CanTradeIfMaxAccountSizeDecreased() public {
    uint expiry = block.timestamp + 1000;
    pmrm_2.setMaxAccountSize(10);

    _depositCash(aliceAcc, 2_000_000e18);
    _depositCash(bobAcc, 2_000_000e18);
    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](9);
    for (uint i = 0; i < transfers.length; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: option,
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        amount: 1e18,
        assetData: ""
      });
    }
    // this should go through
    subAccounts.submitTransfers(transfers, "");

    // assume the owner lower the max asset now
    pmrm_2.setMaxAccountSize(8);

    ISubAccounts.AssetTransfer[] memory newTransfers = new ISubAccounts.AssetTransfer[](3);
    for (uint i = 0; i < newTransfers.length; i++) {
      newTransfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: bobAcc,
        toAcc: aliceAcc,
        asset: option,
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        amount: 1e18,
        assetData: ""
      });
    }

    // closing / having same # of assets should be allowed
    subAccounts.submitTransfers(newTransfers, "");
  }

  function testPMRM_2CannotInteractIfAuctionLive() public {
    _depositCash(bobAcc, 100_000e18);
    weth.mint(address(this), 1e18);
    weth.approve(address(baseAsset), 1e18);
    usdc.approve(address(cash), 1e18);
    baseAsset.deposit(bobAcc, 1e18);

    uint expiry = block.timestamp + 1000;

    MockDutchAuction mockAuction = new MockDutchAuction();
    pmrm_2.setLiquidation(mockAuction);
    mockAuction.startAuction(aliceAcc, 0);

    // CANNOT deposit cash
    vm.expectRevert(IBaseManager.BM_AccountUnderLiquidation.selector);
    cash.deposit(aliceAcc, 1e18);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](1);
    transfers[0] =
      ISubAccounts.AssetTransfer({fromAcc: bobAcc, toAcc: aliceAcc, asset: cash, subId: 0, amount: 1e18, assetData: ""});

    // can also CANNOT transfer cash from another account (doesn't require approvals)
    vm.expectRevert(IBaseManager.BM_AccountUnderLiquidation.selector);
    subAccounts.submitTransfers(transfers, "");

    // CANNOT deposit base asset
    weth.mint(address(this), 1e18);
    weth.approve(address(baseAsset), 1e18);
    vm.expectRevert(IBaseManager.BM_AccountUnderLiquidation.selector);
    baseAsset.deposit(aliceAcc, 1e18);

    // CANNOT transfer cash out
    transfers[0] =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 1e18, assetData: ""});
    vm.expectRevert(IBaseManager.BM_AccountUnderLiquidation.selector);
    subAccounts.submitTransfers(transfers, "");

    // CANNOT transfer long options in (even though risk reducing)
    transfers[0] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: option,
      subId: OptionEncoding.toSubId(expiry, 1500e18, true),
      amount: 1e18,
      assetData: ""
    });

    vm.expectRevert(IBaseManager.BM_AccountUnderLiquidation.selector);
    subAccounts.submitTransfers(transfers, "");

    // CANNOT transfer base asset in
    transfers[0] = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: baseAsset,
      subId: 0,
      amount: 1e18,
      assetData: ""
    });
    vm.expectRevert(IBaseManager.BM_AccountUnderLiquidation.selector);
    subAccounts.submitTransfers(transfers, "");
  }

  function testRevertsIfUsingBadScenarioId() public {
    vm.expectRevert();
    pmrm_2.getMarginAndMarkToMarket(aliceAcc, true, 10000);
  }

  function testPMRM_2CanTradeMoreThanMaxAccountSizeIfAlreadyHadIt() public {
    uint64 expiry = uint64(block.timestamp + 1 weeks);

    _depositCash(aliceAcc, 10_000e18);
    _depositCash(bobAcc, 10_000e18);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](11);
    for (uint i; i < 11; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: option,
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        amount: 0.1e18,
        assetData: ""
      });
    }
    subAccounts.submitTransfers(transfers, "");

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);

    pmrm_2.setMaxAccountSize(8);

    // Close 2 positions against each other
    transfers = new ISubAccounts.AssetTransfer[](2);
    for (uint i; i < 2; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: bobAcc,
        toAcc: aliceAcc,
        asset: option,
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        amount: 0.1e18,
        assetData: ""
      });
    }
    // This can go through since the account size is being reduced
    subAccounts.submitTransfers(transfers, "");

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 10);

    // Cannot then reopen those same positions (inverted)
    vm.expectRevert(IPMRM_2.PMRM_2_TooManyAssets.selector);
    subAccounts.submitTransfers(transfers, "");

    // Can reopen them if the account size is increased
    pmrm_2.setMaxAccountSize(12);
    subAccounts.submitTransfers(transfers, "");
    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);
  }

  function testPMRM_2CanSettlePerpsIfBeyondMaxAssetSize() public {
    uint64 expiry = uint64(block.timestamp + 1 weeks);

    _depositCash(aliceAcc, 10_000e18);
    _depositCash(bobAcc, 10_000e18);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](11);
    for (uint i; i < 10; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: option,
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        amount: 0.1e18,
        assetData: ""
      });
    }
    transfers[10] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: mockPerp,
      subId: 0,
      amount: 10e18,
      assetData: ""
    });
    subAccounts.submitTransfers(transfers, "");
    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);
    pmrm_2.setMaxAccountSize(8);

    weth.mint(address(this), 1000e18);
    weth.approve(address(baseAsset), 1000e18);
    // CANNOT deposit base if that exceeds the account limit
    vm.expectRevert(IPMRM_2.PMRM_2_TooManyAssets.selector);
    baseAsset.deposit(bobAcc, uint(1000e18));

    pmrm_2.setMaxAccountSize(14);
    // we deposit wbtc so we can remove all cash to test the perp settlement
    baseAsset.deposit(bobAcc, uint(1000e18));

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 13);

    pmrm_2.setMaxAccountSize(8);
    cash.withdraw(bobAcc, 10000e18, bob);

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);

    mockPerp.mockAccountPnlAndFunding(bobAcc, 100e18, 100e18);
    pmrm_2.settlePerpsWithIndex(bobAcc);

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 13);
  }

  function testPMRM_2CanGetScenarioMTM() public {
    uint64 expiry = uint64(block.timestamp + 1 weeks);

    _depositCash(aliceAcc, 10_000e18);
    _depositCash(bobAcc, 10_000e18);

    feed.setForwardPrice(expiry, 1300e18, 1e18);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](10);
    for (uint i; i < 10; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: option,
        subId: OptionEncoding.toSubId(expiry, 1500e18 + i * 1e18, true),
        amount: 0.1e18,
        assetData: ""
      });
      feed.setVol(expiry, uint128(1500e18 + i * 1e18), 0.5e18, 1e18);
    }
    subAccounts.submitTransfers(transfers, "");

    IPMRM_2.Portfolio memory portfolio = pmrm_2.arrangePortfolio(aliceAcc);

    int mtm = lib.getScenarioPnL(portfolio, lib.getBasisContingencyScenarios()[0]);
    assertLt(mtm, 0);
    mtm = lib.getScenarioPnL(portfolio, lib.getBasisContingencyScenarios()[1]);
    assertGt(mtm, 0);
  }
}
