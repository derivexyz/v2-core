// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeed.sol";

import "src/Accounts.sol";
import "src/assets/PerpAsset.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/IPerpAsset.sol";

contract UNIT_PerpAssetPNL is Test {
  PerpAsset perp;
  MockManager manager;
  Accounts account;
  MockFeed feed;

  // bot address to set impact prices
  address bot = address(0xb0ba);
  // users
  address alice = address(0xaaaa);
  address bob = address(0xbbbb);
  address charlie = address(0xcccc);
  // accounts
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  int defaultPosition = 1e18;

  uint initPrice = 1500e18;

  function setUp() public {
    // deploy contracts
    account = new Accounts("Lyra", "LYRA");
    feed = new MockFeed();
    manager = new MockManager(address(account));
    perp = new PerpAsset(IAccounts(account), feed);

    // whitelist bots
    perp.setWhitelistManager(address(manager), true);
    perp.setWhitelistBot(bot, true);

    // create account for alice, bob, charlie
    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = account.createAccountWithApproval(charlie, address(this), manager);

    _setPrices(initPrice);

    // open trades
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: perp,
      subId: 0,
      amount: defaultPosition,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }

  function testInitState() public {
    // alice is short, bob is long
    (uint aliceEntryPrice, int alicePnl) = _getEntryPriceAndPNL(aliceAcc);
    (uint bobEntryPrice, int bobPnl) = _getEntryPriceAndPNL(bobAcc);

    assertEq(aliceEntryPrice, initPrice);
    assertEq(bobEntryPrice, initPrice);

    assertEq(alicePnl, 0);
    assertEq(bobPnl, 0);
  }

  // function testIncreasePosition() public {
  //   // alice increase position
  //   vm.prank(alice);
  //   perp.increasePosition(aliceAcc, defaultPosition, "");

  //   // alice's position should be 2
  //   (int alicePosition,,,,) = perp.positions(aliceAcc);
  //   assertEq(alicePosition, 2e18);
  // }

  // // short pay long when mark < index
  // function testApplyNegativeFunding() public {
  //   _setPricesNegativeFunding();

  //   vm.warp(block.timestamp + 1 hours);
  //   // apply funding
  //   perp.updateFundingRate();

  //   // alice is short, bob is long
  //   perp.applyFundingOnAccount(aliceAcc);
  //   perp.applyFundingOnAccount(bobAcc);

  //   // alice paid funding
  //   (, int aliceFunding,,,) = perp.positions(aliceAcc);

  //   // bob received funding
  //   (, int bobFunding,,,) = perp.positions(bobAcc);

  //   assertEq(aliceFunding, -0.75e18);
  //   assertEq(bobFunding, 0.75e18);
  // }

  function _setPrices(uint price) internal {
    uint spot = 1500e18;
    feed.setSpot(spot);
    vm.prank(bot);
    perp.setImpactPrices(int(price), int(price));
  }

  function _getEntryPriceAndPNL(uint acc) internal view returns (uint, int) {
    (uint entryPrice, , int pnl, , ) = perp.positions(acc);
    return (entryPrice, pnl);
  }

}
