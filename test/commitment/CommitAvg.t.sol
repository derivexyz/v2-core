// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";

import "src/commitments/CommitmentAverage.sol";
import "../account/poc-tests/AccountPOCHelper.sol";

contract UNIT_CommitAvg is Test, AccountPOCHelper {
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  // commitment
  CommitmentAverage commitment;
  uint16 constant commitmentWeight = 1;

  uint16[] aliceBids;
  uint16[] aliceAsks;
  uint8[] aliceSubIds;
  uint128[] aliceWeights;
  uint16[] bobBids;
  uint16[] bobAsks;
  uint8[] bobSubIds;
  uint128[] bobWeights;

  function setUp() public {
    vm.label(alice, "alice");
    vm.label(bob, "bob");

    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    // mint $100k dai tokens
    mintDai(alice, 100_000e18);
    mintDai(bob, 100_000e18);

    // allow trades
    // setupMaxAssetAllowancesForAll(bob, bobAcc, orderbook);
    // setupMaxAssetAllowancesForAll(alice, aliceAcc, orderbook);

    // stimulate trade
    addListings();
    // vm.startPrank(orderbook);

    // // alice short call, bob long call
    // tradeOptionWithUSDC(aliceAcc, bobAcc, 1e18, 100e18, subId);
    // vm.stopPrank();

    commitment = new CommitmentAverage(address(account), address(rm), address(daiLending), address(dai));

    vm.warp(block.timestamp + 1 days);
  }

  function testCanDeposit() external {
    vm.startPrank(alice);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(50_000e18); // deposit $50k DAI

    // first deposit
    (uint deposits, uint totalWeight, uint nodeId) = commitment.nodes(alice);
    assertEq(deposits, 50_000e18);
    assertEq(totalWeight, 0);
    assertEq(nodeId, 1);

    // second deposit
    commitment.deposit(10_000e18); // deposit $10k DAI
    (deposits, totalWeight, nodeId) = commitment.nodes(alice);
    assertEq(deposits, 60_000e18);
    assertEq(totalWeight, 0);
    assertEq(nodeId, 1);
    vm.stopPrank();
  }

  function testCanCommit() public {
    // Alice deposit and commit 10 listings
    vm.startPrank(alice);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setAliceComittments();
    commitment.commit(aliceBids, aliceAsks, aliceSubIds, aliceWeights);
    uint64 aliceTime = uint64(block.timestamp);
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);

    // Bob deposit and commit 10 listings
    vm.startPrank(bob);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setBobComittments();
    commitment.commit(bobBids, bobAsks, bobSubIds, bobWeights);
    uint64 bobTime = uint64(block.timestamp);
    vm.stopPrank();

    // verify commitments
    for (uint subId = 0; subId < 5; subId++) {
      for (uint nodeId = 1; nodeId <= 2; nodeId++) {
        if (subId > 2 && nodeId == 2) {
          break; // skip bob since he didn't have commitments here
        }
        verifyNodeCommitment(subId, nodeId, aliceTime, bobTime);
      }
    }

    // validate state
    uint16 bidVol;
    uint16 askVol;
    uint128 commitWeight;
    uint16 avgBidVol;
    uint16 avgAskVol;
    for (uint i = 0; i < 5; i++) {
      (bidVol, askVol, commitWeight) = commitment.state(commitment.COLLECTING(), i);
      uint128 epochTimestamp = commitment.timestamps(commitment.COLLECTING());
      if (i <= 2) {
        avgBidVol = (aliceBids[i] + bobBids[i] * 2) / 3;
        avgAskVol = (aliceAsks[i] + bobAsks[i] * 2) / 3;
        assertEq(bidVol, avgBidVol);
        assertEq(askVol, avgAskVol);
        assertEq(commitWeight, 3);
      } else {
        assertEq(bidVol, aliceBids[i]);
        assertEq(askVol, aliceAsks[i]);
        assertEq(commitWeight, 1);
      }
      assertEq(epochTimestamp, aliceTime);
    }
  }

  function testCanRotateEpochs() public {
    uint16 bidVol;
    uint16 askVol;
    uint128 commitWeight;

    // Alice deposit and commit 10 listings
    vm.startPrank(alice);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setAliceComittments();
    commitment.commit(aliceBids, aliceAsks, aliceSubIds, aliceWeights);
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);

    // Bob deposit and commit 10 listings
    vm.startPrank(bob);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setBobComittments();
    commitment.commit(bobBids, bobAsks, bobSubIds, bobWeights);
    vm.stopPrank();

    // new epoch time elapsed
    vm.warp(block.timestamp + 6 minutes);

    // Bob clears old commits and commits adjusted values to new epoch
    vm.startPrank(bob);
    for (uint8 i = 0; i < 3; i++) {
      bobSubIds[i] = i;
    }
    commitment.clearCommits(bobSubIds);
    (, uint totalWeight,) = commitment.nodes(bob);
    assertEq(totalWeight, 6); // remains unchanged

    setBobComittments();
    bobBids = new uint16[](3);
    bobBids[0] = 65;
    bobBids[1] = 65;
    bobBids[2] = 65;
    bobAsks = new uint16[](3);
    bobAsks[0] = 85;
    bobAsks[1] = 85;
    bobAsks[2] = 85;
    commitment.commit(bobBids, bobAsks, bobSubIds, bobWeights);
    uint64 bobNewTime = uint64(block.timestamp);
    vm.stopPrank();

    // validate new state
    for (uint i = 0; i < 3; i++) {
      (bidVol, askVol, commitWeight) = commitment.state(commitment.COLLECTING(), i);
      uint128 epochTimestamp = commitment.timestamps(commitment.COLLECTING());

      assertEq(bidVol, bobBids[i]);
      assertEq(askVol, bobAsks[i]);
      assertEq(commitWeight, 2);
      assertEq(epochTimestamp, bobNewTime);
    }
    (, totalWeight,) = commitment.nodes(bob);
    assertEq(totalWeight, 12); // commits from last epoch and this one

    // successfuly clear commits and finalizes epoch
    vm.warp(block.timestamp + 12 minutes);
    vm.startPrank(bob);
    commitment.clearCommits(bobSubIds);
    (, totalWeight,) = commitment.nodes(bob);
    assertEq(totalWeight, 6); // remains unchanged
    vm.stopPrank();
    // check subId 3 -> expected to be same as 1st test
    (bidVol, askVol, commitWeight) = commitment.state(commitment.FINALIZED(), 2);
    assertEq(bidVol, 63); // check is same as first commits
    assertEq(askVol, 80); // check is same as first commits
    assertEq(commitWeight, 3); // check is same as first commits
  }

  function testCanExecutePendingCommit() public {
    // Make deposits into first epoch
    vm.startPrank(alice);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setAliceComittments();
    commitment.commit(aliceBids, aliceAsks, aliceSubIds, aliceWeights);
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);

    vm.startPrank(bob);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setBobComittments();
    commitment.commit(bobBids, bobAsks, bobSubIds, bobWeights);
    vm.stopPrank();

    assertEq(commitment.COLLECTING(), 0);
    // start new epoch and rotate epoch count
    vm.warp(block.timestamp + 6 minutes);
    vm.startPrank(bob);
    bobBids = new uint16[](1);
    bobBids[0] = 5;
    bobAsks = new uint16[](1);
    bobAsks[0] = 15;
    bobSubIds = new uint8[](1);
    bobSubIds[0] = 50;
    bobWeights = new uint8[](1);
    bobWeights[0] = 1;
    commitment.commit(bobBids, bobAsks, bobSubIds, bobWeights);
    // uint64 bobNewTime = uint64(block.timestamp);
    vm.stopPrank();

    // confirm epoch rotated
    assertEq(commitment.PENDING(), 0);

    // trade against pending Bob commit
    (, uint weight, uint bobId) = commitment.nodes(bob);
    (,, uint commitWeight,) = commitment.commitments(commitment.PENDING(), bobId, 1);
    (,, uint128 oldStateWeight) = commitment.state(commitment.PENDING(), 1);
    commitment.executeCommit(bobId, 1, 1);
    (, uint newWeight,) = commitment.nodes(bob);
    (,, uint newCommitWeight,) = commitment.commitments(commitment.PENDING(), bobId, 1);
    (uint16 newBidVol, uint16 newAskVol, uint128 newStateWeight) = commitment.state(commitment.PENDING(), 1);

    assertEq(newWeight + 1, weight);
    assertEq(newCommitWeight + 1, commitWeight);
    assertEq(newWeight + 1, weight);
    assertEq(newCommitWeight + 1, commitWeight);
    assertEq(newBidVol, 79); // vol 68 -> 79
    assertEq(newAskVol, 89); // vol 78 -> 89
    assertEq(newStateWeight + 1, oldStateWeight);
  }

  // function testCannotExecuteFinalizedOrCollectingCommit() {

  // }

  function verifyNodeCommitment(uint subId, uint nodeId, uint64 aliceTime, uint64 bobTime) public {
    // verify commitments
    uint16 bidVol;
    uint16 askVol;
    uint128 commitWeight;
    uint64 commitTimestamp;
    (bidVol, askVol, commitWeight, commitTimestamp) = commitment.commitments(commitment.COLLECTING(), nodeId, subId);
    if (nodeId == 1) {
      assertEq(bidVol, aliceBids[subId]);
      assertEq(askVol, aliceAsks[subId]);
      assertEq(commitWeight, aliceWeights[subId]);
      assertEq(commitTimestamp, aliceTime);
    } else {
      assertEq(bidVol, bobBids[subId]);
      assertEq(askVol, bobAsks[subId]);
      assertEq(commitWeight, bobWeights[subId]);
      assertEq(commitTimestamp, bobTime);
    }
  }

  function setAliceComittments() public {
    aliceBids = new uint16[](5);
    aliceBids[0] = 120;
    aliceBids[1] = 115;
    aliceBids[2] = 110;
    aliceBids[3] = 105;
    aliceBids[4] = 100;
    aliceAsks = new uint16[](5);
    aliceAsks[0] = 130;
    aliceAsks[1] = 125;
    aliceAsks[2] = 120;
    aliceAsks[3] = 115;
    aliceAsks[4] = 110;
    aliceSubIds = new uint8[](5);
    for (uint8 i = 0; i < 5; i++) {
      aliceSubIds[i] = i;
    }
    aliceWeights = new uint128[](5);
    for (uint i = 0; i < 5; i++) {
      aliceWeights[i] = 1;
    }
  }

  function setBobComittments() public {
    bobBids = new uint16[](3);
    bobBids[0] = 40;
    bobBids[1] = 40;
    bobBids[2] = 40;
    bobAsks = new uint16[](3);
    bobAsks[0] = 60;
    bobAsks[1] = 60;
    bobAsks[2] = 60;
    bobSubIds = new uint8[](3);
    for (uint8 i = 0; i < 3; i++) {
      bobSubIds[i] = i;
    }
    bobWeights = new uint128[](3);
    for (uint i = 0; i < 3; i++) {
      bobWeights[i] = 2;
    }
  }

  // function testCanExecuteCommit() public {
  //   commitment.commit(100, 1, commitmentWeight);
  //   // this will rotate again -> become only one in COLLECTING

  //   // firt one committing to pending
  //   commitment.commit(110, 1, commitmentWeight);
  //   commitment.commit(110, 2, commitmentWeight);
  //   commitment.commit(116, 3, commitmentWeight);

  //   vm.warp(block.timestamp + 10 minutes);
  //   commitment.executeCommit(3, commitmentWeight);
  //   (uint16 bidVol, uint16 askVol, uint16 totalCommitment,) = commitment.state(commitment.PENDING());

  //   // commitment.executeCommit(1, 1);
  //   assertEq(bidVol, 105);
  //   assertEq(askVol, 115);
  //   assertEq(totalCommitment, commitmentWeight * 2);

  //   // trigger another round
  //   vm.warp(block.timestamp + 10 minutes);
  //   commitment.commit(110, 1, commitmentWeight);

  //   (uint16 bidVolFinal, uint16 askVolFinal,,) = commitment.state(commitment.FINALIZED());
  //   assertEq(bidVolFinal, 105);
  //   assertEq(askVolFinal, 115);
  //   //
  // }

  function addListings() public {
    uint72[11] memory strikes =
      [500e18, 1000e18, 1300e18, 1400e18, 1450e18, 1500e18, 1550e18, 1600e18, 1700e18, 2000e18, 2500e18];

    uint32[7] memory expiries = [1 weeks, 2 weeks, 4 weeks, 8 weeks, 12 weeks, 26 weeks, 52 weeks];
    for (uint s = 0; s < strikes.length; s++) {
      for (uint e = 0; e < expiries.length; e++) {
        optionAdapter.addListing(strikes[s], expiries[e], true);
      }
    }
  }
}
