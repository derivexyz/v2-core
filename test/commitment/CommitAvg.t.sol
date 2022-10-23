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

  uint16[] aliceVols;
  uint8[] aliceSubIds;
  uint128[] aliceWeights;
  uint16[] bobVols;
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
    commitment.commit(aliceVols, aliceSubIds, aliceWeights);
    uint64 aliceTime = uint64(block.timestamp);
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);

    // Bob deposit and commit 10 listings
    vm.startPrank(bob);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setBobComittments();
    commitment.commit(bobVols, bobSubIds, bobWeights);
    uint64 bobTime = uint64(block.timestamp);
    vm.stopPrank();

    // verify commitments
    for (uint subId = 0; subId < 10; subId++) {
      for (uint nodeId = 1; nodeId <= 2; nodeId++) {
        if (subId > 4 && nodeId == 2) {
          break; // skip bob since he didn't have commitments here
        }
        verifyNodeCommitment(subId, nodeId, aliceTime, bobTime);
      }
    }

    // validate state
    uint16 bidVol;
    uint16 askVol;
    uint128 commitWeight;
    uint16 avgVol;
    for (uint i = 0; i < 10; i++) {
      (bidVol, askVol, commitWeight) = commitment.state(commitment.COLLECTING(), i);
      uint128 epochTimestamp = commitment.timestamps(commitment.COLLECTING());
      if (i < 5) {
        avgVol = (aliceVols[i] + bobVols[i] * 2) / 3;
        assertEq(bidVol, avgVol - commitment.RANGE());
        assertEq(askVol, avgVol + commitment.RANGE());
        assertEq(commitWeight, 3);
      } else {
        avgVol = aliceVols[i];
        assertEq(bidVol, avgVol - commitment.RANGE());
        assertEq(askVol, avgVol + commitment.RANGE());
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
    commitment.commit(aliceVols, aliceSubIds, aliceWeights);
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);

    // Bob deposit and commit 10 listings
    vm.startPrank(bob);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setBobComittments();
    commitment.commit(bobVols, bobSubIds, bobWeights);
    vm.stopPrank();

    // new epoch time elapsed
    vm.warp(block.timestamp + 6 minutes);

    // Bob clears old commits and commits adjusted values to new epoch
    vm.startPrank(bob);
    for (uint8 i = 0; i < 5; i++) {
      bobSubIds[i] = i;
    }
    commitment.clearCommits(bobSubIds);
    (, uint totalWeight,) = commitment.nodes(bob);
    assertEq(totalWeight, 10); // remains unchanged

    setBobComittments();
    bobVols = new uint16[](5);
    bobVols[0] = 75;
    bobVols[1] = 75;
    bobVols[2] = 75;
    bobVols[3] = 75;
    bobVols[4] = 75;
    commitment.commit(bobVols, bobSubIds, bobWeights);
    uint64 bobNewTime = uint64(block.timestamp);
    vm.stopPrank();

    // validate new state
    for (uint i = 0; i < 5; i++) {
      (bidVol, askVol, commitWeight) = commitment.state(commitment.COLLECTING(), i);
      uint128 epochTimestamp = commitment.timestamps(commitment.COLLECTING());

      assertEq(bidVol, bobVols[i] - commitment.RANGE());
      assertEq(askVol, bobVols[i] + commitment.RANGE());
      assertEq(commitWeight, 2);
      assertEq(epochTimestamp, bobNewTime);
    }
    (, totalWeight,) = commitment.nodes(bob);
    assertEq(totalWeight, 20); // commits from last epoch and this one

    // successfuly clear commits and finalizes epoch
    vm.warp(block.timestamp + 12 minutes);
    vm.startPrank(bob);
    commitment.clearCommits(bobSubIds);
    (, totalWeight,) = commitment.nodes(bob);
    assertEq(totalWeight, 10); // remains unchanged
    vm.stopPrank();
    // check subId 4 -> expected to be same as 1st test
    (bidVol, askVol, commitWeight) = commitment.state(commitment.FINALIZED(), 4);
    assertEq(bidVol, 63); // check is same as first commits
    assertEq(askVol, 73); // check is same as first commits
    assertEq(commitWeight, 3); // check is same as first commits

  }

  function testCanExecutePendingCommit() public {
    // Make deposits into first epoch
    vm.startPrank(alice);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setAliceComittments();
    commitment.commit(aliceVols, aliceSubIds, aliceWeights);
    vm.stopPrank();
    vm.warp(block.timestamp + 2 minutes);

    vm.startPrank(bob);
    dai.approve(address(commitment), type(uint).max);
    commitment.deposit(10_000e18); // deposit $10k DAI

    setBobComittments();
    commitment.commit(bobVols, bobSubIds, bobWeights);
    vm.stopPrank();

    assertEq(commitment.COLLECTING(), 0);
    // start new epoch and rotate epoch count
    vm.warp(block.timestamp + 6 minutes);
    vm.startPrank(bob);
    bobVols = new uint16[](1);
    bobVols[0] = 10;
    bobSubIds = new uint8[](1);
    bobSubIds[0] = 50;
    bobWeights = new uint8[](1);
    bobWeights[0] = 1;
    commitment.commit(bobVols, bobSubIds, bobWeights);
    // uint64 bobNewTime = uint64(block.timestamp);
    vm.stopPrank();

    // confirm epoch rotated
    assertEq(commitment.PENDING(), 0);

    // trade against pending Bob commit
    (, uint weight, uint bobId) = commitment.nodes(bob);
    (,, uint commitWeight, ) = commitment.commitments(commitment.PENDING(), bobId, 1); 
    (,, uint128 oldStateWeight) = commitment.state(commitment.PENDING(), 1); 
    commitment.executeCommit(bobId, 1, 1);
    (, uint newWeight, ) = commitment.nodes(bob);
    (,, uint newCommitWeight, ) = commitment.commitments(commitment.PENDING(), bobId, 1);
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
      assertEq(bidVol, aliceVols[subId] - commitment.RANGE());
      assertEq(askVol, aliceVols[subId] + commitment.RANGE());
      assertEq(commitWeight, aliceWeights[subId]);
      assertEq(commitTimestamp, aliceTime);
    } else {
      assertEq(bidVol, bobVols[subId] - commitment.RANGE());
      assertEq(askVol, bobVols[subId] + commitment.RANGE());
      assertEq(commitWeight, bobWeights[subId]);
      assertEq(commitTimestamp, bobTime);
    }
  }

  function setAliceComittments() public {
    aliceVols = new uint16[](10);
    aliceVols[0] = 125;
    aliceVols[1] = 120;
    aliceVols[2] = 115;
    aliceVols[3] = 110;
    aliceVols[4] = 105;
    aliceVols[5] = 110;
    aliceVols[6] = 115;
    aliceVols[7] = 120;
    aliceVols[8] = 125;
    aliceVols[9] = 130;
    aliceSubIds = new uint8[](10);
    for (uint8 i = 0; i < 10; i++) {
      aliceSubIds[i] = i;
    }
    aliceWeights = new uint128[](10);
    for (uint i = 0; i < 10; i++) {
      aliceWeights[i] = 1;
    }
  }

  function setBobComittments() public {
    bobVols = new uint16[](5);
    bobVols[0] = 50;
    bobVols[1] = 50;
    bobVols[2] = 50;
    bobVols[3] = 50;
    bobVols[4] = 50;
    bobSubIds = new uint8[](5);
    for (uint8 i = 0; i < 5; i++) {
      bobSubIds[i] = i;
    }
    bobWeights = new uint128[](5);
    for (uint i = 0; i < 5; i++) {
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
