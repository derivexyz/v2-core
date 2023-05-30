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

  function testCannotMergeIfEndAccountIsInsolvent() public {
    // example: alice short a call spread
    // merging another account with a little more calls will "break" the max loss

    uint aliceAcc2 = subAccounts.createAccountWithApproval(alice, address(this), manager);

    // alice short a 2000 call spread, with 100 cash (max loss)
    cash.deposit(aliceAcc, uint(100e18));
    Trade[] memory trade1 = new Trade[](2);
    trade1[0] = Trade(ethOption, 1e18, OptionEncoding.toSubId(expiry1, 2000e18, true));
    trade1[1] = Trade(ethOption, -1e18, OptionEncoding.toSubId(expiry1, 2100e18, true));
    _submitMultipleTrades(aliceAcc, bobAcc, trade1, "");

    // alice short another 0.1 of 2000 calls, which requires isolated margin
    cash.deposit(aliceAcc2, uint(50e18));
    Trade[] memory trade2 = new Trade[](1);
    trade2[0] = Trade(ethOption, 0.1e18, OptionEncoding.toSubId(expiry1, 2000e18, true));
    _submitMultipleTrades(aliceAcc2, bobAcc, trade2, "");

    uint[] memory accsToMerge = new uint[](1);
    accsToMerge[0] = aliceAcc2;
    vm.prank(alice);

    vm.expectRevert(abi.encodeWithSelector(IStandardManager.SRM_PortfolioBelowMargin.selector, aliceAcc, 15e18));
    manager.mergeAccounts(aliceAcc, accsToMerge);
  }
}
