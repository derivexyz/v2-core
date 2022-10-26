// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/mocks/MockERC20.sol";
import "../shared/mocks/MockAsset.sol";
import "../shared/mocks/MockManager.sol";
import "../account/mocks/managers/DumbManager.sol";

import "src/commitments/CommitmentLinkedList.sol";
import "src/Account.sol";

contract UNIT_CommitLinkedList is Test {
  CommitmentLinkedList commitment;
  uint16 constant commitmentWeight = 1;

  uint96 subId = 1;

  MockManager dumbManager;

  MockERC20 usdc;
  MockAsset usdcAsset;
  MockAsset optionAsset;

  uint accId;

  Account account;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    dumbManager = new DumbManager(address(account));

    accId = account.createAccount(address(this), IManager(address(dumbManager)));

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");
    usdcAsset = new MockAsset(IERC20(usdc), IAccount(address(account)), false);

    optionAsset = new MockAsset(IERC20(address(0)), IAccount(address(account)), true);

    commitment =
    new CommitmentLinkedList(address(account), address(usdc), address(usdcAsset), address(optionAsset), address(dumbManager));

    account.approve(address(commitment), accId);

    usdc.mint(address(this), 10000_000000);
    usdc.approve(address(commitment), type(uint).max);
    usdc.approve(address(usdcAsset), type(uint).max);

    commitment.register();

    vm.warp(block.timestamp + 1 days);

    commitment.deposit(1000_000000);

    usdcAsset.deposit(accId, 0, 1000_000000);
  }

  function testCanCommit() public {
    commitment.commit(subId, 95, 105, commitmentWeight);
    commitment.commit(subId, 95, 105, commitmentWeight);
    commitment.commit(subId, 97, 107, commitmentWeight);
    commitment.commit(subId, 100, 110, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 4);
    assertEq(commitment.collectingLength(), 0);
  }

  function testCanExecuteCommit() public {
    commitment.commit(subId, 96, 107, commitmentWeight); // collecting: 1, pending: 0
    commitment.commit(subId, 92, 103, commitmentWeight); // collecting: 2, pending: 0
    commitment.commit(subId, 97, 106, commitmentWeight); // collecting: 3, pending: 0
    commitment.commit(subId, 91, 100, commitmentWeight); // collecting: 3, pending: 0
    assertEq(commitment.collectingLength(), 4);
    assertEq(commitment.collectingWeight(subId, true), commitmentWeight * 4);

    (uint16 lowestBid, uint16 highestBid, uint16 bidLength) = commitment.collectingBidListInfo(subId);
    assertEq(lowestBid, 91);
    assertEq(highestBid, 97);
    assertEq(bidLength, 4);

    (uint16 lowestAsk, uint16 highestAsk, uint16 askLength) = commitment.collectingAskListInfo(subId);
    assertEq(lowestAsk, 100);
    assertEq(highestAsk, 107);
    assertEq(askLength, 4);
  }

  function testCanExecuteCommitMultiple() public {
    uint96[] memory subIds = new uint96[](6);
    subIds[0] = subId;
    subIds[1] = subId;
    subIds[2] = subId;
    subIds[3] = subId;
    subIds[4] = subId;
    subIds[5] = subId;

    uint16[] memory bids = new uint16[](6);
    bids[0] = 90;
    bids[1] = 91;
    bids[2] = 95;

    bids[3] = 93;
    bids[4] = 94;
    bids[5] = 92;

    uint16[] memory asks = new uint16[](6);
    asks[0] = 95;
    asks[1] = 96;
    asks[2] = 97;

    asks[3] = 100;
    asks[4] = 99;
    asks[5] = 98;

    uint64[] memory weights = new uint64[](6);
    for (uint i; i < 6; i++) {
      weights[i] = commitmentWeight;
    }

    commitment.commitMultiple(subIds, bids, asks, weights);
    assertEq(commitment.collectingLength(), 6);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 6);

    (uint16 lowestBid, uint16 highestBid,) = commitment.pendingBidListInfo(subId);
    assertEq(lowestBid, 90);
    assertEq(highestBid, 95);

    // remove 90 vol
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight);
    commitment.executeCommit(accId, subId, true, 95, commitmentWeight);

    (lowestBid, highestBid,) = commitment.pendingBidListInfo(subId);
    assertEq(lowestBid, 91);
    assertEq(highestBid, 94);

    // // remove ask
    commitment.executeCommit(accId, subId, false, 95, commitmentWeight);
    commitment.executeCommit(accId, subId, false, 96, commitmentWeight);

    (uint16 lowestAsk, uint16 highestAsk,) = commitment.pendingAskListInfo(subId);
    assertEq(lowestAsk, 97);
    assertEq(highestAsk, 100);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    (uint16 bestVol,) = commitment.bestFinalizedBids(subId);
    assertEq(bestVol, 94);

    (uint16 bestAsk,) = commitment.bestFinalizedAsks(subId);
    assertEq(bestAsk, 97);
  }

  function testCanExecutePartialSize() public {
    uint96[] memory subIds = new uint96[](3);
    subIds[0] = subId;
    subIds[1] = subId;
    subIds[2] = subId;

    uint16[] memory bids = new uint16[](3);
    bids[0] = 90;
    bids[1] = 92;
    bids[2] = 94;

    uint16[] memory asks = new uint16[](3);
    asks[0] = 96;
    asks[1] = 98;
    asks[2] = 100;

    uint64[] memory weights = new uint64[](3);
    for (uint i; i < 3; i++) {
      weights[i] = commitmentWeight * 2;
    }

    commitment.commitMultiple(subIds, bids, asks, weights);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // remove 1 unit
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight);
    // remove another unit
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight);

    (uint lowestBid, uint highestBid,) = commitment.pendingBidListInfo(subId);
    assertEq(lowestBid, 92);
    assertEq(highestBid, 94);

    // // remove ask
    commitment.executeCommit(accId, subId, false, 96, commitmentWeight);
    commitment.executeCommit(accId, subId, false, 98, commitmentWeight);
    commitment.executeCommit(accId, subId, false, 100, commitmentWeight * 2);

    (uint16 lowestAsk, uint16 highestAsk,) = commitment.pendingAskListInfo(subId);
    assertEq(lowestAsk, 96);
    assertEq(highestAsk, 98);
  }

  function testExecuteWillTrade() public {
    uint96[] memory subIds = new uint96[](2);
    subIds[0] = subId;
    subIds[1] = subId;

    uint16[] memory bids = new uint16[](2);
    bids[0] = 90;
    bids[1] = 92;

    uint16[] memory asks = new uint16[](2);
    asks[0] = 96;
    asks[1] = 98;

    uint64[] memory weights = new uint64[](2);
    weights[0] = commitmentWeight;
    weights[1] = commitmentWeight;

    commitment.commitMultiple(subIds, bids, asks, weights);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // execute against 90 bid
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight);
    // executge against 92 bid
    commitment.executeCommit(accId, subId, true, 92, commitmentWeight);

    // check that executing against bids will update executor balance
    assertEq(account.getBalance(accId, optionAsset, subId), -int(uint(2 * commitmentWeight)));

    // // remove ask
    // execute against 90 bid
    commitment.executeCommit(accId, subId, false, 96, commitmentWeight);
    commitment.executeCommit(accId, subId, false, 98, commitmentWeight);

    // end balace is 0 because sell 2 + buy 2
    assertEq(account.getBalance(accId, optionAsset, subId), 0);
  }

  // function testShouldRolloverBlankIfPendingIsEmpty() public {
  //   commitment.commit(subId, 95, 105, commitmentWeight); // collecting: 1, pending: 0
  //   commitment.commit(subId, 96, 106, commitmentWeight); // collecting: 2, pending: 0

  //   vm.warp(block.timestamp + 10 minutes);
  //   commitment.checkRollover(); // collecting: 0, pending: 2

  //   assertEq(commitment.pendingLength(), 2);
  //   assertEq(commitment.pendingWeight(subId), commitmentWeight * 2);

  //   commitment.executeCommit(accId,subId, true, 0, commitmentWeight);
  //   commitment.executeCommit(accId,subId, true, 1, commitmentWeight);

  //   commitment.commit(subId, 95, 105, commitmentWeight); // collecting: 1, pending: 0

  //   vm.warp(block.timestamp + 10 minutes);

  //   commitment.checkRollover();

  //   (uint16 bestVol, uint64 commitments, uint64 nodeId, uint64 timestamp) = commitment.bestFinalizedBids(subId);
  //   assertEq(bestVol, 0);
  //   assertEq(nodeId, 0);
  //   assertEq(commitments, 0);
  //   assertEq(timestamp, 0);

  //   assertEq(commitment.pendingLength(), 1);
  // }
}
