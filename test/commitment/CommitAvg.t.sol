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
    expiry = block.timestamp + 604800;
    strike = 1500e18;
    subId = optionAdapter.addListing(strike, expiry, true);
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
    vm.stopPrank();
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
}
