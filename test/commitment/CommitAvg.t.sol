// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "src/commitments/CommitmentAverage.sol";
import "../account/poc-tests/AccountPOCHelper.sol";

contract UNIT_CommitAvg is Test, AccountPOCHelper {
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  // fake option property
  uint strike;
  uint expiry;
  uint subId;

// commitment 
  CommitmentAverage commitment;
  uint16 constant commitmentWeight = 1;

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
    (uint256 deposits, uint256 totalWeight, uint256 nodeId) = commitment.nodes(alice);
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

  function testCanBeFirstCommit() public {
    vm.startPrank(alice);
    commitment.deposit(10_000e18); // deposit $10k DAI

    // commit to 10 listings
    uint16[] memory vols = new uint16[](10);
    vols[0] = 125;
    vols[1] = 120;
    vols[2] = 115;
    vols[3] = 110;
    vols[4] = 105;
    vols[5] = 110;
    vols[6] = 115;
    vols[7] = 120;
    vols[8] = 125;
    vols[9] = 130;
    uint8[] memory subIds = new uint8[](10);
    for (uint8 i = 0; i < 10; i++) {
      subIds[i] = i;
    }
    uint128[] memory weights = new uint128[](10);
    for (uint i = 0; i < 10; i++) {
      weights[i] = 1;
    }
    commitment.commit(vols, subIds, weights);
    vm.stopPrank();

    
    for (uint i = 0; i < 10; i++) {
      // validate new commitment
      (uint16 bidVol, uint16 askVol, uint128 weight, uint64 timestamp) = commitment.commitments(commitment.COLLECTING(), 1, 0);
      assertEq(bidVol, vols[i] + commitment.RANGE());
      assertEq(askVol, vols[i] - commitment.RANGE());
      assertEq(weight, weights[i]);
      assertEq(timestamp, block.timestamp);

      // validate new state
      (uint16 avgBid, uint16 avgAsk, uint128 totWeight) = commitment.state(commitment.COLLECTING(), i);
      uint128 epochTimestamp = commitment.timestamps(commitment.COLLECTING());
      assertEq(avgBid, vols[i] + commitment.RANGE());
      assertEq(avgAsk, vols[i] - commitment.RANGE());
      assertEq(totWeight, weights[i]);
      assertEq(epochTimestamp, block.timestamp);
    }
  }


  // function testCanCommit() public {
  //   commitment.commit(100, 1, commitmentWeight);

  //   (uint16 bidVol, uint16 askVol, uint16 totalCommitment,) = commitment.state(commitment.COLLECTING());
  //   assertEq(bidVol, 95);
  //   assertEq(askVol, 105);
  //   assertEq(totalCommitment, commitmentWeight);

  //   // this will rotate again -> become only one in COLLECTING

  //   // firt one committing to pending
  //   commitment.commit(110, 1, commitmentWeight);
  //   // commit another
  //   commitment.commit(116, 2, commitmentWeight);
  //   (uint16 bidVol2, uint16 askVol2,,) = commitment.state(commitment.COLLECTING());

  //   assertEq(bidVol2, 113 - 5);
  //   assertEq(askVol2, 113 + 5);
  // }

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
    uint72[11] memory strikes = [
      500e18, 1000e18, 1300e18, 1400e18, 1450e18, 1500e18, 1550e18, 1600e18, 1700e18, 2000e18, 2500e18
    ];

    uint32[7] memory expiries = [
      1 weeks, 2 weeks, 4 weeks, 8 weeks, 12 weeks, 26 weeks, 52 weeks
    ];
    for (uint s = 0; s < strikes.length; s++) {
      for (uint e = 0; e < expiries.length; e++) {
        optionAdapter.addListing(strikes[s], expiries[e], true);
      }
    }
  }

}
