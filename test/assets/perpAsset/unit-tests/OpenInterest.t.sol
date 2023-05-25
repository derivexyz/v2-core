// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "src/Accounts.sol";
import "src/assets/PerpAsset.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import "src/interfaces/IPerpAsset.sol";

contract UNIT_PerpOIAndCap is Test {
  PerpAsset perp;
  MockManager manager;
  MockManager manager2;
  Accounts account;
  MockFeeds feed;

  // users
  address alice = address(0xaaaa);
  address bob = address(0xbbbb);
  address charlie = address(0xccc);

  // accounts
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  int128 spot = 1500e18;

  function setUp() public {
    account = new Accounts("Lyra", "LYRA");
    feed = new MockFeeds();

    manager = new MockManager(address(account));
    manager2 = new MockManager(address(account));
    perp = new PerpAsset(IAccounts(account), 0.0075e18);

    perp.setSpotFeed(feed);
    perp.setPerpFeed(feed);

    manager = new MockManager(address(account));

    feed.setSpot(uint(int(spot)), 1e18);

    // whitelist keepers
    perp.setWhitelistManager(address(manager), true);
    perp.setWhitelistManager(address(manager2), true);

    // create account for alice and bob
    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = account.createAccountWithApproval(charlie, address(this), manager);
  }

  function testCanSetTotalPositionCapOnManager() public {
    perp.setTotalPositionCap(manager, 100e18);
    assertEq(perp.totalPositionCap(manager), 100e18);
  }

  function testCanChangeManagerIfCapNotSet() public {
    _transferPerp(aliceAcc, bobAcc, 100e18);
    account.changeManager(aliceAcc, manager2, "");
    assertEq(perp.totalPosition(manager2), 100e18);
  }

  function testCannotChangeManagerIfExceedCap() public {
    _transferPerp(aliceAcc, bobAcc, 100e18);
    perp.setTotalPositionCap(manager2, 1e18);
    vm.expectRevert(IPerpAsset.PA_ManagerChangeExceedCap.selector);
    account.changeManager(aliceAcc, manager2, "");
  }

  function testChangeManagerWillMigrateTotalPosition() public {
    // alice opens short, bob opens long
    _transferPerp(aliceAcc, bobAcc, 100e18);

    account.changeManager(aliceAcc, manager2, "");

    assertEq(perp.totalPosition(manager), 100e18);
    assertEq(perp.totalPosition(manager2), 100e18);
  }

  function testTradeIncreaseOIAndTotalPos() public {
    // alice opens short, bob opens long
    _transferPerp(aliceAcc, bobAcc, 100e18);
    assertEq(perp.openInterest(0), 100e18);
    assertEq(perp.totalPosition(manager), 200e18);
  }

  function testClosePositionDecreaseOIAndTotalPosition() public {
    // alice opens short, bob opens long
    _transferPerp(aliceAcc, bobAcc, 100e18);
    // open interest: 100, total position: 200

    // close half of the positions
    _transferPerp(bobAcc, aliceAcc, 50e18);
    assertEq(perp.openInterest(0), 50e18);
    assertEq(perp.totalPosition(manager), 100e18);
  }

  function testOIAndTotalPosIncreaseIfOpenNew() public {
    // alice opens short, bob opens long
    _transferPerp(aliceAcc, bobAcc, 100e18);
    // open interest: 100, total position: 200

    // alice long 200 with charlie, making alice now +100, bob: +100, charlie: -200
    _transferPerp(charlieAcc, aliceAcc, 200e18);

    assertEq(perp.openInterest(0), 200e18);
    assertEq(perp.totalPosition(manager), 400e18);
  }

  function testAndTradeCrossManagers() public {
    uint newAccount = account.createAccountWithApproval(address(0x1234), address(this), manager2);

    // alice opens short on manager 1, new account long on manager 2
    _transferPerp(aliceAcc, newAccount, 100e18);

    assertEq(perp.openInterest(0), 100e18);
    assertEq(perp.totalPosition(manager), 100e18);
    assertEq(perp.totalPosition(manager2), 100e18);
  }

  function _transferPerp(uint from, uint to, int amount) internal {
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: from, toAcc: to, asset: perp, subId: 0, amount: amount, assetData: ""});
    account.submitTransfer(transfer, "");
  }
}
