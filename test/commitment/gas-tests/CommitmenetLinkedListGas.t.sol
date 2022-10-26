// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/commitments/CommitmentLinkedList.sol";
import "src/Account.sol";

import "../../account/mocks/managers/DumbManager.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockManager.sol";

contract CommitmentLinkedListGas is Script {
  uint ownAcc;
  CommitmentLinkedList commitment;

  uint expiry;
  uint96 subId = 1;

  MockManager dumbManager;
  MockERC20 usdc;
  MockAsset usdcAsset;
  MockAsset optionAsset;

  Account account;
  uint accId;

  uint16 constant commitmentWeight = 1;

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    // gas tests

    uint gasBefore = gasleft();
    commitment.register();
    uint gasAfter = gasleft();
    console.log("gas register", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.deposit(10000e6);
    gasAfter = gasleft();
    console.log("gas deposit", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(subId, 90, 100, commitmentWeight); // collecting: 1, pending: 0
    gasAfter = gasleft();
    console.log("gas commit: #1 for subId", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(subId, 92, 102, commitmentWeight);
    gasAfter = gasleft();
    console.log("gas commit: #2 for subId", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(subId, 92, 102, commitmentWeight); // collecting: 2, pending: 0
    gasAfter = gasleft();
    console.log("gas commit: exisiting vols", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(subId, 94, 105, commitmentWeight); // collecting: 2, pending: 0
    gasAfter = gasleft();
    console.log("gas commit: #3 vol", gasBefore - gasAfter);

    console2.log("----------------------------------");

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    // add 100 to the queue
    _commitMultiple(100, 1, 0);

    // add to the end of the linked list
    gasBefore = gasleft();
    commitment.commit(0, 200, 220, commitmentWeight);
    gasAfter = gasleft();
    console.log("gas commit: 101th in linked list", gasBefore - gasAfter);

    vm.warp(block.timestamp + 20 minutes);
    gasBefore = gasleft();
    commitment.checkRollover();
    gasAfter = gasleft();
    console.log("gas rollover 1 subIds", gasBefore - gasAfter);

    console2.log("----------------------------------");

    gasBefore = gasleft();
    uint gasAdd100SubIds = _commitMultiple(100, 100, 5);
    gasAfter = gasleft();
    console.log("gas commitMultiple: first one to commit to 100 subIds:", gasAdd100SubIds);

    gasBefore = gasleft();
    gasAdd100SubIds = _commitMultiple(100, 100, 7);
    gasAfter = gasleft();
    console.log("gas commitMultiple: second to commit to 100 subIds:", gasAdd100SubIds);

    gasBefore = gasleft();
    gasAdd100SubIds = _commitMultiple(100, 100, 8);
    gasAfter = gasleft();
    console.log("gas commitMultiple: third to commit to 100 subIds:", gasAdd100SubIds);

    // console2.log("----------------------------------");

    // (uint bestBid_1,,, uint96 _timestamp) = commitment.bestFinalizedBids(0);
    // (uint bestBid_2,,, uint96 _timestamp2) = commitment.bestFinalizedBids(1);

    // // add to 200 subId
    // _commitMultiple(200, 200);

    // // roll to pending
    // vm.warp(block.timestamp + 30 minutes);
    // commitment.checkRollover();

    // // roll to finalized

    // vm.warp(block.timestamp + 40 minutes);
    // gasBefore = gasleft();
    // commitment.checkRollover();
    // gasAfter = gasleft();

    // console.log("gas rollover 200 subIds x 1 each in queue", gasBefore - gasAfter);

    // (,,, uint64 timestamp) = commitment.bestFinalizedBids(0);
    // (,,, uint64 timestamp2) = commitment.bestFinalizedBids(1);

    // vm.stopBroadcast();
  }

  function _commitMultiple(uint total, uint subIdCount, uint16 offSet) internal returns (uint gasCost) {
    uint96[] memory subIds = new uint96[](total);

    uint16[] memory bids = new uint16[](total);

    uint16[] memory asks = new uint16[](total);

    uint64[] memory weights = new uint64[](total);
    for (uint16 i; i < total; i++) {
      subIds[i] = uint96(i % subIdCount);
      bids[i] = 50 + offSet + (i);
      asks[i] = 60 + offSet + (i);
      weights[i] = 1;
    }

    uint gasBefore = gasleft();
    commitment.commitMultiple(subIds, bids, asks, weights);
    uint gasAfter = gasleft();
    return gasBefore - gasAfter;
  }

  function deployMockSystem() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");
    usdcAsset = new MockAsset(IERC20(usdc), IAccount(address(account)), false);

    optionAsset = new MockAsset(IERC20(address(0)), IAccount(address(account)), true);

    usdc.mint(msg.sender, 100000e6);

    dumbManager = new MockManager(address(account));

    commitment =
    new CommitmentLinkedList(address(account), address(usdc), address(usdcAsset), address(optionAsset), address(dumbManager));

    usdc.approve(address(commitment), type(uint).max);
    usdc.approve(address(usdcAsset), type(uint).max);

    accId = account.createAccount(address(this), dumbManager);
    usdcAsset.deposit(accId, 0, 10000e6);
  }
}
