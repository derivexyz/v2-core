// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../../src/assets/PerpAsset.sol";
import "../../../../src/interfaces/ISubAccounts.sol";
import "../../../../src/interfaces/IManagerWhitelist.sol";
import "../../../shared/mocks/MockSpotDiffFeed.sol";

contract UNIT_PerpAssetHook is Test {
  PerpAsset perp;
  MockManager manager;
  address account;
  MockFeeds spotFeed;
  MockSpotDiffFeed perpFeed;

  function setUp() public {
    account = address(0xaa);

    spotFeed = new MockFeeds();
    perpFeed = new MockSpotDiffFeed(spotFeed);

    manager = new MockManager(account);

    perp = new PerpAsset(ISubAccounts(account));
    perp.setRateBounds(0.0075e18);

    perp.setSpotFeed(spotFeed);
    perp.setPerpFeed(perpFeed);

    spotFeed.setSpot(1500e18, 1e18);
  }

  function testCannotCallHandleAdjustmentFromNonAccount() public {
    vm.expectRevert(IManagerWhitelist.MW_OnlyAccounts.selector);
    ISubAccounts.AssetAdjustment memory adjustment = ISubAccounts.AssetAdjustment(0, perp, 0, 0, 0x00);
    perp.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testCannotExecuteHandleAdjustmentIfManagerIsNotWhitelisted() public {
    /* this could happen if someone is trying to transfer our cash asset to an account controlled by malicious manager */
    ISubAccounts.AssetAdjustment memory adjustment = ISubAccounts.AssetAdjustment(0, perp, 0, 0, 0x00);
    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);

    vm.prank(account);
    perp.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testShouldReturnFinalBalance() public {
    perp.setWhitelistManager(address(manager), true);
    int preBalance = 0;
    int amount = 100;
    ISubAccounts.AssetAdjustment memory adjustment = ISubAccounts.AssetAdjustment(0, perp, 0, amount, 0x00);
    vm.prank(account);
    (int postBalance, bool needAllowance) = perp.handleAdjustment(adjustment, 0, preBalance, manager, address(this));
    assertEq(postBalance, amount);
    assertEq(needAllowance, true);
  }
}
