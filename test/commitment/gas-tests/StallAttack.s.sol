// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/Account.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";

import "forge-std/console2.sol";

import "../../account/mocks/assets/OptionToken.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../account/mocks/assets/lending/Lending.sol";
import "../../account/mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../../account/mocks/assets/lending/InterestRateModel.sol";
import "../../account/mocks/managers/PortfolioRiskPOCManager.sol";
import "../../shared/mocks/MockERC20.sol";
import "src/commitments/CommitmentAverage.sol";
import "./SimulationHelper.sol";


// run  with `forge script StallAttackScript --fork-url http://localhost:8545` against anvil
// OptionToken deployment fails when running outside of localhost

contract StallAttack is SimulationHelper {
  /* address setup */
  address node = vm.addr(2);
  address attacker = vm.addr(3);

  /* 60 min vol feed: 5 min increments */
  uint16[12] AMMVolFeed = [
    100, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250
  ];
  uint16 AMMSpread = 5;

  /**
   * @dev Simulation
   *  - 1x active node
   *  - 1x attacker node
   *  - 7x strikes and 7x expiries
   *  - 5min epochs
   *  - $500 deposit per subId
   */
  function run() external {
    console2.log("SETTING UP SIMULATION...");
    _deployAccountAndStables();
    _deployOptionAndManager();
    _deployCommitment();
    _addListings();
    _setupParams(1500e18);
      
    console2.log("SETTING UP ATTACKER ACCOUNT...");
    vm.startBroadcast(owner);
    uint attackerAccId = account.createAccount(attacker, IManager(address(manager)));
    vm.stopBroadcast();
    _depositToAccount(attacker, attackerAccId, 1_000_000e18);

    /* deposit to node */
    console2.log("DEPOSITING TO NODE...");
    _depositToNode(node, 100_000e18);

    /* begin sim */
    uint16 currBid;
    uint16 currAsk;
    uint128 currWeight;
    uint nodeDeposits;
    uint nodeTotWeight;
    for (uint i; i < AMMVolFeed.length; i++) {

      /* place standard commitments */ 
      vm.startBroadcast(node);
      (uint16[] memory bids, 
      uint16[] memory asks, 
      uint8[] memory subIds, 
      uint128[] memory weights) = _generateFlatCommitments(AMMVolFeed[i], AMMSpread, 3, 1);
      commitment.commit(bids, asks, subIds, weights);

      (, , uint128 commitWeight, ) = commitment.commitments(commitment.COLLECTING(), 1, 1);
      console2.log("commit weight for subId 1: %s", commitWeight);

      /* warp 5 min and rotate */
      vm.warp(block.timestamp + 5 minutes + 1 seconds);
      commitment.checkRotateBlocks();
      commitment.clearCommits(subIds);
      vm.stopBroadcast();

      /* print state */
      console.log("Epoch %s", i + 1);
      (currBid,
      currAsk,
      currWeight) = commitment.state(commitment.PENDING(), 3);
      (nodeDeposits, nodeTotWeight, ) = commitment.nodes(node);
      console.log("$1500, 4 week commitment weight %s", currWeight);
      console.log("committed capital", nodeTotWeight);
      console.log("------------------");
    }
  }

  /**
   * @dev Creates commitments based on single AMM feed with 0 skew across strikes/expiries for simplicity.
   *      Assumes there are always 49x subIds to commit to.
   * @param ammVol vol from AMM feed / quote
   * @param ammSpread bid / ask spread from AMM feed / quote
   * @param spreadBuffer static amount to add to each AMM spread
   * @param weight weight behind each commitment
   */
  function _generateFlatCommitments(
    uint16 ammVol, uint16 ammSpread, uint16 spreadBuffer, uint128 weight
  ) public returns (
    uint16[] memory bids, uint16[] memory asks, uint8[] memory subIds, uint128[] memory weights
  ) {
    require(ammVol > (ammSpread + spreadBuffer), "spread + buffer > vol");

    bids = new uint16[](49);
    asks = new uint16[](49);
    subIds = new uint8[](49);
    weights = new uint128[](49);
    for (uint8 i; i < 49; i++) {
      bids[i] = ammVol - ammSpread - spreadBuffer;
      asks[i] = ammVol + ammSpread + spreadBuffer;
      subIds[i] = i;
      weights[i] = weight;
    }
  }

  // function generateAttackResponse(
  //   uint16 ammVol, uint16 ammSpread, uint8 subIdToDefend, uint16 spreadMultiple, uint16 weightMultiple
  // ) public {

  // }

  function _addListings() public {
    uint72[7] memory strikes = [1000e18, 1300e18, 1400e18, 1500e18, 1600e18, 1700e18, 2000e18];

    uint32[7] memory expiries = [1 weeks, 2 weeks, 4 weeks, 8 weeks, 12 weeks, 26 weeks, 52 weeks];
    for (uint s = 0; s < strikes.length; s++) {
      for (uint e = 0; e < expiries.length; e++) {
        optionAdapter.addListing(strikes[s], expiries[e], true);
      }
    }
  }

  function _printCommits() public {
    (, , uint128 col, ) = commitment.commitments(commitment.COLLECTING(), 1, 1);
    (, , uint128 pen, ) = commitment.commitments(commitment.PENDING(), 1, 1);
    (, , uint128 fin, ) = commitment.commitments(commitment.FINALIZED(), 1, 1);
    console2.log("post clear commits");
     console2.log(col, pen, fin);
  }
}