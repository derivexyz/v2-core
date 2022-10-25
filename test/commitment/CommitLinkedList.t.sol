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

  Account account;

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");
    dumbManager = new DumbManager(address(account));

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");
    usdcAsset = new MockAsset(IERC20(usdc), IAccount(address(account)), false);

    commitment = new CommitmentLinkedList(address(account), address(usdc), address(usdcAsset), address(dumbManager));

    usdc.mint(address(this), 10000_000000);
    usdc.approve(address(commitment), type(uint).max);

    commitment.register();

    vm.warp(block.timestamp + 1 days);

    commitment.deposit(100_000000);
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
    assertEq(commitment.collectingWeight(subId), commitmentWeight * 4);

    (uint16 lowestBid, uint16 highestBid) = commitment.collectingBidListInfo(subId);
    assertEq(lowestBid, 91);
    assertEq(highestBid, 97);

    (uint16 lowestAsk, uint16 highestAsk) = commitment.collectingAskListInfo(subId);
    assertEq(lowestAsk, 100);
    assertEq(highestAsk, 107);
  }

  // function testCanExecuteCommitMultiple() public {
  //   uint96 subId2 = 2;

  //   uint96[] memory subIds = new uint96[](6);
  //   subIds[0] = subId;
  //   subIds[1] = subId;
  //   subIds[2] = subId;
  //   subIds[3] = subId2;
  //   subIds[4] = subId2;
  //   subIds[5] = subId2;

  //   uint16[] memory bids = new uint16[](6);
  //   bids[0] = 90;
  //   bids[1] = 91;
  //   bids[2] = 92;

  //   bids[3] = 93;
  //   bids[4] = 94;
  //   bids[5] = 95;

  //   uint16[] memory asks = new uint16[](6);
  //   asks[0] = 95;
  //   asks[1] = 96;
  //   asks[2] = 97;

  //   asks[3] = 98;
  //   asks[4] = 99;
  //   asks[5] = 100;

  //   uint64[] memory weights = new uint64[](6);
  //   for (uint i; i < 6; i++) {
  //     weights[i] = commitmentWeight;
  //   }

  //   commitment.commitMultiple(subIds, bids, asks, weights);
  //   assertEq(commitment.collectingLength(), 6);

  //   vm.warp(block.timestamp + 10 minutes);
  //   commitment.checkRollover();

  //   assertEq(commitment.pendingLength(), 6);

  //   // remove third for subId
  //   commitment.executeCommit(subId, true, 2, commitmentWeight);

  //   // remove third for subId2
  //   commitment.executeCommit(subId2, true, 2, commitmentWeight);

  //   vm.warp(block.timestamp + 10 minutes);
  //   commitment.checkRollover();

  //   (uint16 bestVol,,,) = commitment.bestFinalizedBids(subId);
  //   assertEq(bestVol, 91);

  //   (uint16 bestVol2,,,) = commitment.bestFinalizedBids(subId2);
  //   assertEq(bestVol2, 94);
  // }

  // function testShouldRolloverBlankIfPendingIsEmpty() public {
  //   commitment.commit(subId, 95, 105, commitmentWeight); // collecting: 1, pending: 0
  //   commitment.commit(subId, 96, 106, commitmentWeight); // collecting: 2, pending: 0

  //   vm.warp(block.timestamp + 10 minutes);
  //   commitment.checkRollover(); // collecting: 0, pending: 2

  //   assertEq(commitment.pendingLength(), 2);
  //   assertEq(commitment.pendingWeight(subId), commitmentWeight * 2);

  //   commitment.executeCommit(subId, true, 0, commitmentWeight);
  //   commitment.executeCommit(subId, true, 1, commitmentWeight);

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
