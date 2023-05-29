pragma solidity ^0.8.13;

import "./TestStandardManagerBase.t.sol";

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

  // test merging accounts that are all above water
  function testCanMergeAccounts() public {
    cash.deposit(aliceAcc, uint(10000e18));
    cash.deposit(bobAcc, uint(10000e18));
    cash.deposit(charlieAcc, uint(10000e18));

    Trade[] memory trades = new Trade[](4);
    trades[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, 2000e18, true));
    trades[1] = Trade(btcOption, 1e18, OptionEncoding.toSubId(expiry1, 30000e18, true));
    trades[2] = Trade(ethPerp, 1e18, 0);
    trades[3] = Trade(btcPerp, 1e18, 0);

    // alice short 1 eth call + 1 btc call + 1 eth perp + 1 btc perp with bob
    _submitMultipleTrades(aliceAcc, bobAcc, trades, "");
    // alice short 1 eth call + 1 btc call + 1 eth perp + 1 btc perp with charlie
    _submitMultipleTrades(aliceAcc, charlieAcc, trades, "");

    uint[] memory accsToMerge = new uint[](1);
    accsToMerge[0] = bobAcc;

    // alice cannot merge bob's account into hers
    vm.expectRevert(IBaseManager.BM_MergeOwnerMismatch.selector);
    vm.prank(alice);
    manager.mergeAccounts(aliceAcc, accsToMerge);

    // bob transfer his account to alice
    vm.prank(bob);
    subAccounts.transferFrom(bob, alice, bobAcc);

    // and now they can merge!
    vm.prank(alice);
    manager.mergeAccounts(aliceAcc, accsToMerge);

    assertEq(_getCashBalance(aliceAcc), 20000e18);
    assertEq(_getPerpBalance(ethPerp, aliceAcc), -1e18);
    assertEq(_getPerpBalance(btcPerp, aliceAcc), -1e18);

    assertEq(_getCashBalance(bobAcc), 0);
  }
}
