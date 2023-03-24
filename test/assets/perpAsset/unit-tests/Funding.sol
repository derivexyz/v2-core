// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockFeed.sol";

import "src/Accounts.sol";
import "src/assets/PerpAsset.sol";
import "src/interfaces/IAccounts.sol";

contract UNIT_PerpAssetFunding is Test {
  PerpAsset perp;
  MockManager manager;
  Accounts account;
  MockFeed feed;

  // bot address to set impact prices
  address bot = address(0xb0ba);
  // users
  address alice = address(0xaaaa);
  address bob = address(0xbbbb);
  // accounts
  uint aliceAcc;
  uint bobAcc;

  int defaultPosition = 1e18;

  function setUp() public {
    // deploy contracts
    account = new Accounts("Lyra", "LYRA");
    feed = new MockFeed();
    manager = new MockManager(address(account));
    perp = new PerpAsset(IAccounts(account), feed);

    // whitelist bots
    perp.setWhitelistManager(address(manager), true);
    perp.setWhitelistBot(bot, true);

    // create account for alice and bob
    aliceAcc = account.createAccount(alice, manager);
    bobAcc = account.createAccount(bob, manager);

    _setDefaultPrices();

    // open trades
    vm.prank(alice);
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

  function testSetImpactPrices() public {
    // set impact price
    vm.prank(bot);
    perp.setImpactPrices(1550e18, 1500e18);
    assertEq(perp.impactAskPrice(), 1550e18);
    assertEq(perp.impactBidPrice(), 1500e18);
  }

  function testUpdateFundingRate() public {
    perp.updateFundingRate();
  }

  function testApplyFunding() public {
    // apply funding
    perp.applyFundingOnAccount(aliceAcc);
    perp.applyFundingOnAccount(bobAcc);

    // // check funding rate
    // assertEq(perp.getFundingRate(aliceAcc), 0);
    // assertEq(perp.getFundingRate(bobAcc), 0);

    // // check funding amount
    // assertEq(perp.getFundingAmount(aliceAcc), 0);
    // assertEq(perp.getFundingAmount(bobAcc), 0);

    // // check funding amount
    // assertEq(perp.getFundingAmount(aliceAcc), 0);
    // assertEq(perp.getFundingAmount(bobAcc), 0);

    // // check funding amount
    // assertEq(perp.getFundingAmount(aliceAcc), 0);
    // assertEq(perp.getFundingAmount(bobAcc), 0);
  }

  function _setDefaultPrices() internal returns (uint, int, int) {
    uint spot = 1500e18;
    int iap = 1520e18;
    int ibp = 1480e18;
    feed.setSpot(spot);

    vm.prank(bot);
    perp.setImpactPrices(iap, ibp);
    return (spot, iap, ibp);
  }
}
