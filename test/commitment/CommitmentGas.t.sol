// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/commitments/CommitmentBest.sol";
import "src/commitments/CommitmentAverage.sol";
import "src/Account.sol";

import "../account/mocks/managers/DumbManager.sol";
import "../shared/mocks/MockERC20.sol";
import "../shared/mocks/MockAsset.sol";
import "../shared/mocks/MockManager.sol";

contract CommitmentBestGas is Script {
  uint ownAcc;
  CommitmentBest commitment;

  uint expiry;
  uint96 subId = 1;

  MockManager dumbManager;
  MockERC20 usdc;
  MockAsset usdcAsset;

  Account account;

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    // gas tests

    uint gasBefore = gasleft();
    commitment.register();
    uint gasAfter = gasleft();
    console.log("gas register", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.deposit(100000e6);
    gasAfter = gasleft();
    console.log("gas deposit", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(subId, 95, 105, 1);
    gasAfter = gasleft();
    console.log("gas commit#1", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(subId, 96, 106, 1);
    gasAfter = gasleft();
    console.log("gas commit#2", gasBefore - gasAfter);

    console2.log("----------------------------------");

    _commitMultiple(500, 5);
    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover(); // pending: 102

    vm.warp(block.timestamp + 20 minutes);
    gasBefore = gasleft();
    commitment.checkRollover(); // pending: 102
    gasAfter = gasleft();

    console.log("gas rollover 5 subIds x 200 each in queue", gasBefore - gasAfter);

    console2.log("----------------------------------");

    (uint bestBid_1,,,uint96 _timestamp) = commitment.bestFinalizedBids(0);
    (uint bestBid_2,,,uint96 _timestamp2) = commitment.bestFinalizedBids(1);


    // add to 200 subId
    _commitMultiple(200, 200);  

    // roll to pending
    vm.warp(block.timestamp + 30 minutes);
    commitment.checkRollover();

    // roll to finalized

    vm.warp(block.timestamp + 40 minutes);
    gasBefore = gasleft();
    commitment.checkRollover();
    gasAfter = gasleft();

    console.log("gas rollover 200 subIds x 1 each in queue", gasBefore - gasAfter);

    (,,,uint64 timestamp) = commitment.bestFinalizedBids(0);
    (,,,uint64 timestamp2) = commitment.bestFinalizedBids(1);

    vm.stopBroadcast();
  }

  function _commitMultiple(uint total, uint subIdCount) internal {
    uint96[] memory subIds = new uint96[](total);

    uint16[] memory bids = new uint16[](total);

    uint16[] memory asks = new uint16[](total);

    uint64[] memory weights = new uint64[](total);
    for (uint16 i; i < total; i++) {
      subIds[i] = uint96(i % subIdCount);
      bids[i] = 50 + (i % 30);
      asks[i] = 60 + (i % 30);
      weights[i] = 5e6;
    }

    uint gasBefore = gasleft();
    commitment.commitMultiple(subIds, bids, asks, weights);
    uint gasAfter = gasleft();
    console.log("gas commitMultiple (#subId, #each, gas):", subIdCount, (total / subIdCount), gasBefore - gasAfter);
  }

  function deployMockSystem() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");
    usdcAsset = new MockAsset(IERC20(usdc), IAccount(address(account)), false);

    usdc.mint(msg.sender, 100000e6);

    dumbManager = new MockManager(address(account));

    commitment = new CommitmentBest(address(account), address(usdc), address(usdcAsset), address(dumbManager));

    usdc.approve(address(commitment), type(uint).max);
  }
}

// contract CommitmentAvgGas is Script {
//   uint ownAcc;
//   CommitmentAverage commitment;

//   uint expiry;

//   function run() external {
//     vm.startBroadcast();

//     deployMockSystem();

//     // gas tests
//     uint gasBefore = gasleft();
//     commitment.commit(100, 1, 1);
//     uint gasAfter = gasleft();
//     console.log("gas commit#1", gasBefore - gasAfter);

//     gasBefore = gasleft();
//     commitment.commit(102, 2, 1);
//     gasAfter = gasleft();
//     console.log("gas commit#2", gasBefore - gasAfter);

//     gasBefore = gasleft();
//     commitment.commit(104, 3, 1);
//     gasAfter = gasleft();
//     console.log("gas commit#3", gasBefore - gasAfter);

//     vm.warp(block.timestamp + 5 minutes);

//     gasBefore = gasleft();
//     commitment.executeCommit(1, 1);
//     gasAfter = gasleft();
//     console.log("execute#1", gasBefore - gasAfter);

//     gasBefore = gasleft();
//     commitment.executeCommit(2, 1);
//     gasAfter = gasleft();
//     console.log("execute#2", gasBefore - gasAfter);

//     gasBefore = gasleft();
//     commitment.executeCommit(3, 1);
//     gasAfter = gasleft();
//     console.log("execute#3", gasBefore - gasAfter);

//     vm.stopBroadcast();
//   }

//   function _commitMultiple(uint count) internal {
//     for (uint i; i < count; i++) {
//       commitment.commit(104, uint16(i), 1);
//     }
//   }

//   function deployMockSystem() public {
//     commitment = new CommitmentAverage();
//   }
// }
