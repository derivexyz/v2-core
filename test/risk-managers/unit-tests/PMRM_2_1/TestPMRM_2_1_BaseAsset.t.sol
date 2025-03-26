// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../risk-managers/unit-tests/PMRM_2_1/utils/PMRM_2_1TestBase.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";

contract TestPMRM_2_1_BaseAsset is PMRM_2_1TestBase {
  function testCannotSetInvalidFeeds() public {
    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidCollateralAsset.selector);
    pmrm_2_1.setCollateralSpotFeed(address(option), ISpotFeed(address(0)));

    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidCollateralAsset.selector);
    pmrm_2_1.setCollateralSpotFeed(address(mockPerp), ISpotFeed(address(0)));

    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidCollateralAsset.selector);
    pmrm_2_1.setCollateralSpotFeed(address(cash), ISpotFeed(address(0)));
  }

  function testCanDepositBase() public {
    baseAsset.setTotalPositionCap(pmrm_2_1, 0);
    baseAsset.setWhitelistManager(address(pmrm_2_1), true);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    vm.expectRevert(IBaseManager.BM_AssetCapExceeded.selector);
    baseAsset.deposit(bobAcc, 100e18);

    baseAsset.setTotalPositionCap(pmrm_2_1, 100e18);
    baseAsset.deposit(bobAcc, 100e18);
  }

  function testCanWithdrawEvenPastCap() public {
    baseAsset.setWhitelistManager(address(pmrm_2_1), true);
    baseAsset.setTotalPositionCap(pmrm_2_1, 100e18);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(bobAcc, 100e18);

    baseAsset.setTotalPositionCap(pmrm_2_1, 0);

    vm.startPrank(bob);
    baseAsset.withdraw(bobAcc, 10e18, bob);
  }

  function testCannotTransferBaseFromAnotherManager() public {
    baseAsset.setWhitelistManager(address(pmrm_2_1), true);

    baseAsset.setTotalPositionCap(pmrm_2_1, 100e18);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(bobAcc, 100e18);

    // decrease the cap to 0
    baseAsset.setTotalPositionCap(pmrm_2_1, 0);

    PMRMLib_2_1 newLib = new PMRMLib_2_1();

    // other PMRM_2_1
    PMRM_2_1 newImp = new PMRM_2_1Public();
    TransparentUpgradeableProxy proxy;

    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidMaxExpiries.selector);
    proxy = new TransparentUpgradeableProxy(
      address(newImp),
      address(this),
      abi.encodeWithSelector(
        newImp.initialize.selector,
        subAccounts,
        cash,
        option,
        mockPerp,
        auction,
        IPMRM_2_1.Feeds({
          spotFeed: ISpotFeed(feed),
          stableFeed: ISpotFeed(stableFeed),
          forwardFeed: IForwardFeed(feed),
          interestRateFeed: IInterestRateFeed(feed),
          volFeed: IVolFeed(feed)
        }),
        viewer,
        newLib,
        31
      )
    );

    vm.expectRevert(IPMRM_2_1.PMRM_2_1_InvalidMaxExpiries.selector);
    proxy = new TransparentUpgradeableProxy(
      address(newImp),
      address(this),
      abi.encodeWithSelector(
        newImp.initialize.selector,
        subAccounts,
        cash,
        option,
        mockPerp,
        auction,
        IPMRM_2_1.Feeds({
          spotFeed: ISpotFeed(feed),
          stableFeed: ISpotFeed(stableFeed),
          forwardFeed: IForwardFeed(feed),
          interestRateFeed: IInterestRateFeed(feed),
          volFeed: IVolFeed(feed)
        }),
        viewer,
        newLib,
        0
      )
    );

    proxy = new TransparentUpgradeableProxy(
      address(newImp),
      address(this),
      abi.encodeWithSelector(
        newImp.initialize.selector,
        subAccounts,
        cash,
        option,
        mockPerp,
        auction,
        IPMRM_2_1.Feeds({
          spotFeed: ISpotFeed(feed),
          stableFeed: ISpotFeed(stableFeed),
          forwardFeed: IForwardFeed(feed),
          interestRateFeed: IInterestRateFeed(feed),
          volFeed: IVolFeed(feed)
        }),
        viewer,
        newLib,
        11
      )
    );

    PMRM_2_1Public newManager = PMRM_2_1Public(address(proxy));

    newManager.setScenarios(Config.get_2_1DefaultScenarios());
    baseAsset.setWhitelistManager(address(newManager), true);

    newManager.setCollateralSpotFeed(address(baseAsset), ISpotFeed(feed));
    newLib.setCollateralParameters(
      address(baseAsset),
      IPMRMLib_2_1.CollateralParameters({isEnabled: true, isRiskCancelling: true, MMHaircut: 0.02e18, IMHaircut: 0.01e18})
    );

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
