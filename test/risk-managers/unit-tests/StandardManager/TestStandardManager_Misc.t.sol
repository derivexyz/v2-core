// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";
import {ISRMPortfolioViewer} from "../../../../src/interfaces/ISRMPortfolioViewer.sol";
import {IStandardManager} from "../../../../src/interfaces/IStandardManager.sol";
import {MockManager} from "../../../shared/mocks/MockManager.sol";
import {MockOption} from "../../../shared/mocks/MockOptionAsset.sol";
import "../../../../scripts/config-local.sol";

contract UNIT_TestStandardManager_Misc is TestStandardManagerBase {
  function testCanTransferCash() public {
    int amount = 1000e18;

    cash.deposit(aliceAcc, uint(amount));

    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: cash,
      subId: 0,
      amount: amount,
      assetData: ""
    });

    subAccounts.submitTransfer(transfer, "");
  }

  function testCannotSetInvalidMarginParams() public {
    IStandardManager.OptionMarginParams memory params = getDefaultSRMOptionParam();

    vm.expectRevert(IStandardManager.SRM_InvalidOptionMarginParams.selector);
    params.maxSpotReq = 1.5e18;
    manager.setOptionMarginParams(ethMarketId, params);

    //    vm.expectRevert(IStandardManager.SRM_InvalidOptionMarginParams.selector);
    //    params.maxSpotReq = -1;
    //    manager.setOptionMarginParams(ethMarketId, params);
  }

  function testCanEnableBorrowing() public {
    manager.setBorrowingEnabled(true);
    assertEq(manager.borrowingEnabled(), true);
  }

  function testCanHaveNegativeCashIfBorrowingEnabled() public {
    manager.setBorrowingEnabled(true);
    cash.deposit(aliceAcc, uint(50000e18));

    // can only borrow 50% of base asset's value
    manager.setBaseAssetMarginFactor(btcMarketId, 0.5e18, 1e18);

    // bob deposit 1 WBTC
    wbtc.mint(address(this), 1e18);
    wbtc.approve(address(wbtcAsset), 1e18);
    wbtcAsset.deposit(bobAcc, uint(1e18));

    // bob can borrow against this long call
    cash.withdraw(bobAcc, uint(btcSpot / 2), bob);

    assertEq(_getCashBalance(bobAcc), -int(btcSpot / 2));
  }

  function testCannotTradeMoreThanMaxAccountSize() public {
    manager.setMaxAccountSize(10);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](11);
    for (uint i; i < 11; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: ethOption,
        subId: i,
        amount: 100e18,
        assetData: ""
      });
    }

    vm.expectRevert(IStandardManager.SRM_TooManyAssets.selector);
    subAccounts.submitTransfers(transfers, "");
  }

  function testCanTradeMoreThanMaxAccountSizeIfAlreadyHadIt() public {
    cash.deposit(aliceAcc, 10_000e18);
    cash.deposit(bobAcc, 10_000e18);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](11);
    for (uint i; i < 11; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: ethOption,
        subId: OptionEncoding.toSubId(expiry2, 1500e18 + i * 1e18, true),
        amount: 0.1e18,
        assetData: ""
      });
    }
    subAccounts.submitTransfers(transfers, "");

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);

    manager.setMaxAccountSize(8);

    // Close 2 positions against each other
    transfers = new ISubAccounts.AssetTransfer[](2);
    for (uint i; i < 2; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: bobAcc,
        toAcc: aliceAcc,
        asset: ethOption,
        subId: OptionEncoding.toSubId(expiry2, 1500e18 + i * 1e18, true),
        amount: 0.1e18,
        assetData: ""
      });
    }
    // This can go through since the account size is being reduced
    subAccounts.submitTransfers(transfers, "");

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 10);

    // Cannot then reopen those same positions (inverted)
    vm.expectRevert(IStandardManager.SRM_TooManyAssets.selector);
    subAccounts.submitTransfers(transfers, "");

    // Can reopen them if the account size is increased
    manager.setMaxAccountSize(12);
    subAccounts.submitTransfers(transfers, "");
    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);
  }

  function testCanSettlePerpsIfBeyondMaxAssetSize() public {
    cash.deposit(aliceAcc, 10_000e18);
    cash.deposit(bobAcc, 10_000e18);

    ISubAccounts.AssetTransfer[] memory transfers = new ISubAccounts.AssetTransfer[](11);
    for (uint i; i < 10; i++) {
      transfers[i] = ISubAccounts.AssetTransfer({
        fromAcc: aliceAcc,
        toAcc: bobAcc,
        asset: ethOption,
        subId: OptionEncoding.toSubId(expiry2, 1500e18 + i * 1e18, true),
        amount: 0.1e18,
        assetData: ""
      });
    }
    transfers[10] = ISubAccounts.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: ethPerp,
      subId: 0,
      amount: 10e18,
      assetData: ""
    });
    subAccounts.submitTransfers(transfers, "");
    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);
    manager.setMaxAccountSize(8);

    manager.setBaseAssetMarginFactor(btcMarketId, 0.5e18, 1e18);

    wbtc.mint(address(this), 1000e18);
    wbtc.approve(address(wbtcAsset), 1000e18);
    // CANNOT deposit base if that exceeds the account limit
    vm.expectRevert(IStandardManager.SRM_TooManyAssets.selector);
    wbtcAsset.deposit(bobAcc, uint(1000e18));

    manager.setMaxAccountSize(14);
    // we deposit wbtc so we can remove all cash to test the perp settlement
    wbtcAsset.deposit(bobAcc, uint(1000e18));

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 13);

    manager.setMaxAccountSize(8);
    cash.withdraw(bobAcc, 10000e18, bob);

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 12);

    ethPerp.mockAccountPnlAndFunding(bobAcc, 100e18, 100e18);
    manager.settlePerpsWithIndex(bobAcc);

    assertEq(subAccounts.getAccountBalances(bobAcc).length, 13);
  }

  function testCanHaveNegativeCashWhenBorrowingBecomesDisabled() public {
    // deposit cash to borrow later
    cash.deposit(aliceAcc, 80_000e18);

    // Make sure base can be used as margin
    manager.setBaseAssetMarginFactor(btcMarketId, 0.8e18, 0.8e18);

    // Add base asset to borrow against
    wbtc.mint(address(this), 5e18);
    wbtc.approve(address(wbtcAsset), 5e18);
    wbtcAsset.deposit(bobAcc, uint(5e18));

    // borrowing the cash reverts as borrowing is disabled
    vm.prank(bob);
    vm.expectRevert(IStandardManager.SRM_NoNegativeCash.selector);
    cash.withdraw(bobAcc, uint(btcSpot), bob);

    // once enabled we can borrow against the btc
    manager.setBorrowingEnabled(true);
    vm.prank(bob);
    cash.withdraw(bobAcc, uint(btcSpot), bob);

    // now bob has a negative cash balance
    assertEq(_getCashBalance(bobAcc), -int(btcSpot));

    // disable borrowing
    manager.setBorrowingEnabled(false);

    // bob cannot borrow more
    vm.prank(bob);
    vm.expectRevert(IStandardManager.SRM_NoNegativeCash.selector);
    cash.withdraw(bobAcc, uint(1e18), bob);

    // bob can still transfer assets without reverting
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: bobAcc,
      toAcc: aliceAcc,
      asset: wbtcAsset,
      subId: 0,
      amount: 1e18,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");

    // bob can still receive cash in a trade
    transfer =
      ISubAccounts.AssetTransfer({fromAcc: aliceAcc, toAcc: bobAcc, asset: cash, subId: 0, amount: 1e18, assetData: ""});
    subAccounts.submitTransfer(transfer, "");
    assertEq(_getCashBalance(bobAcc), -int(btcSpot) + 1e18);

    // bob can still deposit cash
    cash.deposit(bobAcc, 1e18);

    // and can borrow more when borrowing is re-enabled
    manager.setBorrowingEnabled(true);
    cash.withdraw(bobAcc, 1e18, bob);
  }
}
