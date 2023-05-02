// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeed.sol";

import "../../../../src/assets/PerpAsset.sol";
import "../../../../src/interfaces/IAccounts.sol";

contract UNIT_PerpAssetHook is Test {
  PerpAsset perp;
  MockManager manager;
  address account;
  MockFeed feed;

  function setUp() public {
    account = address(0xaa);

    feed = new MockFeed();

    manager = new MockManager(account);

    perp = new PerpAsset(IAccounts(account), 0.0075e18);

    perp.setSpotFeed(feed);

    feed.setSpot(1500e18);
  }

  function testCannotCallHandleAdjustmentFromNonAccount() public {
    vm.expectRevert(IManagerWhitelist.MW_OnlyAccounts.selector);
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, perp, 0, 0, 0x00);
    perp.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testCannotExecuteHandleAdjustmentIfManagerIsNotWhitelisted() public {
    /* this could happen if someone is trying to transfer our cash asset to an account controlled by malicious manager */
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, perp, 0, 0, 0x00);
    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);

    vm.prank(account);
    perp.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testShouldReturnFinalBalance() public {
    perp.setWhitelistManager(address(manager), true);
    int preBalance = 0;
    int amount = 100;
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, perp, 0, amount, 0x00);
    vm.prank(account);
    (int postBalance, bool needAllowance) = perp.handleAdjustment(adjustment, 0, preBalance, manager, address(this));
    assertEq(postBalance, amount);
    assertEq(needAllowance, true);
  }

  function testWillNotRevertOnLegalManagerUpdate() public {
    perp.setWhitelistManager(address(manager), true);

    vm.prank(account);
    perp.handleManagerChange(0, manager);
  }
}
