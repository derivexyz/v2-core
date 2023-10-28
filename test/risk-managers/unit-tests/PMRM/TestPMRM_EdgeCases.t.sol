// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../../src/risk-managers/PMRM.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";

contract UNIT_TestPMRM_EdgeCases is PMRMSimTest {
  function testPMRM_perpTransfer() public {
    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".SinglePerp");

    _depositCash(aliceAcc, 2_000 ether);
    _depositCash(bobAcc, 2_000 ether);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_unsupportedAsset() public {
    MockOption newAsset = new MockOption(subAccounts);
    // newAsset.setWhitelistManager(address(pmrm), true);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: IAsset(address(newAsset)), balance: 1_000 ether, subId: 0});
    vm.expectRevert(IPMRM.PMRM_UnsupportedAsset.selector);
    _doBalanceTransfer(aliceAcc, bobAcc, balances);
  }

  function testPMRM_invalidSpotShock() public {
    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](1);
    scenarios[0] = IPMRM.Scenario({spotShock: 3e18 + 1, volShock: IPMRM.VolShockDirection.None});

    vm.expectRevert(IPMRM.PMRM_InvalidSpotShock.selector);
    pmrm.setScenarios(scenarios);

    // but this works fine
    scenarios[0].spotShock = 3e18;
    pmrm.setScenarios(scenarios);
  }

  function testPMRM_notFoundError() public {
    IPMRM.ExpiryHoldings[] memory expiryData = new IPMRM.ExpiryHoldings[](0);
    vm.expectRevert(IPMRM.PMRM_FindInArrayError.selector);
    pmrm.findInArrayPub(expiryData, 0, 0);
  }

  function testPMRM_noScenarios() public {
    // Cannot set no scenarios
    vm.expectRevert(IPMRM.PMRM_InvalidScenarios.selector);
    pmrm.setScenarios(new IPMRM.Scenario[](0));
  }

  function testPMRM_invalidGetMarginState() public {
    IPMRM.Scenario[] memory scenarios = new IPMRM.Scenario[](0);

    IPMRM.Portfolio memory portfolio;
    vm.expectRevert(IPMRMLib.PMRML_InvalidGetMarginState.selector);
    pmrm.getMarginAndMarkToMarketPub(portfolio, true, scenarios);

    vm.expectRevert(IPMRMLib.PMRML_InvalidGetMarginState.selector);
    pmrm.getMarginAndMarkToMarketPub(portfolio, true, scenarios);
  }

  function testPMRM_CannotTradeIfExceed_MaxAssets() public {
    uint expiry = block.timestamp + 1000;
    pmrm.setMaxAccountSize(10);
    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](pmrm.maxAccountSize() + 1);
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
    vm.expectRevert(IPMRM.PMRM_TooManyAssets.selector);
    subAccounts.submitTransfers(transfers, "");
  }

  function testPMRM_CanTradeIfMaxAccountSizeDecreased() public {
    uint expiry = block.timestamp + 1000;
    pmrm.setMaxAccountSize(10);

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
    pmrm.setMaxAccountSize(8);

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

  function testPMRMCanOnlyDepositCashIfLiveAuction() public {
    _depositCash(bobAcc, 100_000e18);
    weth.mint(address(this), 1e18);
    weth.approve(address(baseAsset), 1e18);
    baseAsset.deposit(bobAcc, 1e18);

    uint expiry = block.timestamp + 1000;

    MockDutchAuction mockAuction = new MockDutchAuction();
    pmrm.setLiquidation(mockAuction);
    mockAuction.startAuction(aliceAcc, 0);

    // Can always deposit cash
    _depositCash(aliceAcc, 1e18);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](1);
    transfers[0] =
      ISubAccounts.AssetTransfer({fromAcc: bobAcc, toAcc: aliceAcc, asset: cash, subId: 0, amount: 1e18, assetData: ""});

    // can also transfer cash from another account (doesn't require approvals)
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
    pmrm.getMarginAndMarkToMarket(aliceAcc, true, 10000);
  }
}
