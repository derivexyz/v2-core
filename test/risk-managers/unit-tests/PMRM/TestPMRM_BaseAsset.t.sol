pragma solidity ^0.8.18;

import "./PMRMTestBase.sol";

import "forge-std/console2.sol";
import "src/periphery/PerpSettlementHelper.sol";
import "src/periphery/OptionSettlementHelper.sol";

contract TestPMRM_BaseAsset is PMRMTestBase {
  function testCanDepositBase() public {
    baseAsset.setWhitelistManager(address(pmrm), true);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    vm.expectRevert(IPMRM.PMRM_ExceededBaseOICap.selector);
    baseAsset.deposit(bobAcc, 100e18);

    baseAsset.setOICap(pmrm, 100e18);
    baseAsset.deposit(bobAcc, 100e18);
  }

  function testCanTransferEvenPastCap() public {
    baseAsset.setWhitelistManager(address(pmrm), true);
    baseAsset.setOICap(pmrm, 100e18);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(bobAcc, 100e18);

    baseAsset.setOICap(pmrm, 0);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: cash, balance: 20e18, subId: 0});
    _doBalanceTransfer(bobAcc, aliceAcc, balances);
  }

  function testCanWithdrawEvenPastCap() public {
    baseAsset.setWhitelistManager(address(pmrm), true);
    baseAsset.setOICap(pmrm, 100e18);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(bobAcc, 100e18);

    baseAsset.setOICap(pmrm, 0);

    vm.startPrank(bob);
    baseAsset.withdraw(bobAcc, 10e18, bob);
  }

  function testCannotTransferBaseFromAnotherManager() public {
    baseAsset.setWhitelistManager(address(pmrm), true);

    baseAsset.setOICap(pmrm, 100e18);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(bobAcc, 100e18);

    // decrease the cap to 0
    baseAsset.setOICap(pmrm, 0);

    // other PMRM
    PMRM newManager = new PMRMPublic(
      subAccounts,
      cash,
      option,
      mockPerp,
      IOptionPricing(optionPricing),
      baseAsset,
      IDutchAuction(address(0)),
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
    baseAsset.setWhitelistManager(address(newManager), true);
    // create new account for that manager
    uint newAcc = subAccounts.createAccount(address(this), IManager(address(newManager)));
    baseAsset.setOICap(newManager, type(uint).max);
    weth.mint(address(this), 100e18);
    weth.approve(address(baseAsset), 100e18);
    baseAsset.deposit(newAcc, 100e18);

    ISubAccounts.AssetBalance[] memory balances = new ISubAccounts.AssetBalance[](1);
    balances[0] = ISubAccounts.AssetBalance({asset: baseAsset, balance: 20e18, subId: 0});

    // bob can transfer out
    _doBalanceTransfer(bobAcc, newAcc, balances);

    // bob cannot transfer back in
    vm.expectRevert(IPMRM.PMRM_ExceededBaseOICap.selector);
    _doBalanceTransfer(newAcc, bobAcc, balances);
  }
}
