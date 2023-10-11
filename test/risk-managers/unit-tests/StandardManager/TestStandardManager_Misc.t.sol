// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";
import {ISRMPortfolioViewer} from "../../../../src/interfaces/ISRMPortfolioViewer.sol";
import {IStandardManager} from "../../../../src/interfaces/IStandardManager.sol";
import {MockManager} from "../../../shared/mocks/MockManager.sol";
import {MockOption} from "../../../shared/mocks/MockOptionAsset.sol";
import "../../../../scripts/config.sol";

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

    vm.expectRevert(IStandardManager.SRM_InvalidOptionMarginParams.selector);
    params.maxSpotReq = -1;
    manager.setOptionMarginParams(ethMarketId, params);
  }

  function testCanEnableBorrowing() public {
    manager.setBorrowingEnabled(true);
    assertEq(manager.borrowingEnabled(), true);
  }

  function testCanHaveNegativeCashIfBorrowingEnabled() public {
    manager.setBorrowingEnabled(true);
    cash.deposit(aliceAcc, uint(50000e18));

    // can only borrow 50% of base asset's value
    manager.setBaseMarginDiscountFactor(btcMarketId, 0.5e18);

    // bob deposit 1 WBTC
    wbtc.mint(address(this), 1e18);
    wbtc.approve(address(wbtcAsset), 1e18);
    wbtcAsset.deposit(bobAcc, uint(1e18));

    // bob can borrow against this long call
    cash.withdraw(bobAcc, uint(btcSpot / 2), bob);

    assertEq(_getCashBalance(bobAcc), -int(btcSpot / 2));
  }

  function testCannotChangeFromBadManagerWithInvalidAsset() public {
    // create accounts with bad manager
    MockManager badManager = new MockManager(address(subAccounts));
    MockOption badAsset = new MockOption(subAccounts);
    uint badAcc = subAccounts.createAccount(address(this), badManager);
    uint badAcc2 = subAccounts.createAccount(address(this), badManager);

    // create bad positions
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: badAcc,
      toAcc: badAcc2,
      asset: badAsset,
      subId: 0,
      amount: 100e18,
      assetData: ""
    });
    subAccounts.submitTransfer(transfer, "");

    // alice migrate to a our manager
    vm.expectRevert(IStandardManager.SRM_UnsupportedAsset.selector);
    subAccounts.changeManager(badAcc, manager, "");
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

    vm.expectRevert(ISRMPortfolioViewer.SRM_TooManyAssets.selector);
    subAccounts.submitTransfers(transfers, "");
  }
}
