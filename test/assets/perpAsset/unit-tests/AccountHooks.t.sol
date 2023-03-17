// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockManager.sol";

import "../../../../src/assets/PerpAsset.sol";
import "../../../../src/interfaces/IAccounts.sol";

contract UNIT_PerpAssetHook is Test {
  PerpAsset perp;
  MockManager manager;
  address account;

  function setUp() public {
    account = address(0xaa);

    manager = new MockManager(account);

    perp = new PerpAsset(IAccounts(account));
  }

  function testCannotCallHandleAdjustmentFromNonAccount() public {
    vm.expectRevert(ITrustedAsset.TA_NotAccount.selector);
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, perp, 0, 0, 0x00);
    perp.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testCannotExecuteHandleAdjustmentIfManagerIsNotWhitelisted() public {
    /* this could happen if someone is trying to transfer our cash asset to an account controlled by malicious manager */
    AccountStructs.AssetAdjustment memory adjustment = AccountStructs.AssetAdjustment(0, perp, 0, 0, 0x00);
    vm.expectRevert(ITrustedAsset.TA_UnknownManager.selector);

    vm.prank(account);
    perp.handleAdjustment(adjustment, 0, 0, manager, address(this));
  }

  function testWillNotRevertOnLegalManagerUpdate() public {
    perp.setWhitelistManager(address(manager), true);

    vm.prank(account);
    perp.handleManagerChange(0, manager);
  }
}
