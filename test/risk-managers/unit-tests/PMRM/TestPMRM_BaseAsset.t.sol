// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMTestBase.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";

contract TestPMRM_BaseAsset is PMRMTestBase {
  function testCanDepositBase() public {
    baseAsset.setTotalPositionCap(pmrm, 0);
    baseAsset.setWhitelistManager(address(pmrm), true);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    vm.expectRevert(IBaseManager.BM_AssetCapExceeded.selector);
    baseAsset.deposit(bobAcc, 100e18);

    baseAsset.setTotalPositionCap(pmrm, 100e18);
    baseAsset.deposit(bobAcc, 100e18);
  }

  function testCanWithdrawEvenPastCap() public {
    baseAsset.setWhitelistManager(address(pmrm), true);
    baseAsset.setTotalPositionCap(pmrm, 100e18);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(bobAcc, 100e18);

    baseAsset.setTotalPositionCap(pmrm, 0);

    vm.startPrank(bob);
    baseAsset.withdraw(bobAcc, 10e18, bob);
  }

  function testCannotTransferBaseFromAnotherManager() public {
    baseAsset.setWhitelistManager(address(pmrm), true);

    baseAsset.setTotalPositionCap(pmrm, 100e18);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(bobAcc, 100e18);

    // decrease the cap to 0
    baseAsset.setTotalPositionCap(pmrm, 0);

    PMRMLib pmrmLib = new PMRMLib();

    // other PMRM
    PMRM newManager = new PMRMPublic(
      subAccounts,
      cash,
      option,
      mockPerp,
      baseAsset,
      IDutchAuction(new MockDutchAuction()),
      IPMRM.Feeds({
        spotFeed: ISpotFeed(feed),
        stableFeed: ISpotFeed(stableFeed),
        forwardFeed: IForwardFeed(feed),
        interestRateFeed: IInterestRateFeed(feed),
        volFeed: IVolFeed(feed),
        settlementFeed: ISettlementFeed(feed)
      }),
      viewer,
      pmrmLib
    );

    newManager.setScenarios(getDefaultScenarios());

    baseAsset.setWhitelistManager(address(newManager), true);
    // create new account for that manager
    uint newAcc = subAccounts.createAccount(address(this), IManager(address(newManager)));
    baseAsset.setTotalPositionCap(newManager, type(uint).max);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(newAcc, 100e18);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: baseAsset, balance: 20e18, subId: 0});

    // bob can transfer out
    _doBalanceTransfer(bobAcc, newAcc, balances);

    // bob cannot transfer back in
    vm.expectRevert(IBaseManager.BM_AssetCapExceeded.selector);
    _doBalanceTransfer(newAcc, bobAcc, balances);
  }
}
