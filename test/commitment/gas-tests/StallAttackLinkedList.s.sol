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
import "src/commitments/CommitmentLinkedList.sol";
import "./SimulationHelper.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

// run  with `forge script StallAttackScript --fork-url http://localhost:8545` against anvil
// OptionToken deployment fails when running outside of localhost

contract StallAttackLinkedList is SimulationHelper {
  CommitmentLinkedList commitment;

  /* address setup */
  address honestStaker = vm.addr(2);
  address attacker = vm.addr(3);

  /* staker ids */
  uint64 honestStakeId;

  /* 60 min vol feed: 5 min increments */
  uint16[12] AMMVolFeed = [100, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250, 250];
  uint16 AMMSpread = 5;

  uint8 ACTIVE_SUBIDS = 49;

  /* attack response params */
  uint16 SPREAD_MUL = 2;
  uint64 WEIGHT_MUL = 2;
  uint DEPOSIT_CAP = 3_000_000e18; // $ 3mln DAI
  uint64 previousCommitWeight = 1; // crude way for node to keep track of last time attack

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

    /* register staker / attacker */
    vm.startBroadcast(honestStaker);
    honestStakeId = commitment.register();
    vm.stopBroadcast();

    /* deposit to node */
    console2.log("DEPOSITING TO NODE...");
    _depositToNode(honestStaker, 100_000e18);

    /* begin sim */
    uint128 currLength;
    uint stakerDeposits;
    for (uint i; i < AMMVolFeed.length; i++) {
      /* place standard commitments */
      (uint16[] memory bids, uint16[] memory asks, uint96[] memory subIds, uint64[] memory weights) =
        _generateFlatCommitments(AMMVolFeed[i], AMMSpread, 3, 1);

      /* determine whether response is needed */
      (uint16 newBid, uint16 newAsk, uint96 attackSubId, uint64 newWeight) =
        _generateAttackResponse(SPREAD_MUL, WEIGHT_MUL);

      /* deposit more if needed */
      _depositToNode(honestStaker, commitment.getCollatLockUp(newWeight, attackSubId, newBid, newAsk));


      if (newWeight > 0 && i != 0) {
        // attack started
        console2.log("attack spotted... %s", newWeight);
        bids[attackSubId] = newBid;
        asks[attackSubId] = newAsk;
        weights[attackSubId] = newWeight;
      }

      vm.startBroadcast(honestStaker);
      commitment.commitMultiple(subIds, bids, asks, weights);

      _printCommits(1, honestStakeId);

      /* warp 5 min and rotate */
      vm.warp(block.timestamp + 5 minutes + 1 seconds);
      commitment.checkRollover();
      // commitment.clearCommits(subIds); // allow node to reuse deposits for new commits
      vm.stopBroadcast();

      /* stall attack */
      vm.startBroadcast(attacker);
      (,, uint16 bestAsk, uint64 askWeight) = commitment.pendingBestBidAsk(1); // assume only one in queue
      commitment.executeCommit(
        attackerAccId, 
        1, // subId
        false, // isBid = false
        bestAsk,
        askWeight);

      vm.stopBroadcast();

      /* get state */
      (,, currLength) = commitment.pendingBidListInfo(1);
      (, , stakerDeposits,,) = commitment.stakers(honestStaker);

      /* print new state */
      console.log("Epoch %s", i + 1);
      console.log("$1000, 1 week queue length %s", currLength);
      console.log("active deposits", stakerDeposits);
      console.log("------------------ \n");

      /* calculate arb loss */
      // todo: actually do calcs
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
  function _generateFlatCommitments(uint16 ammVol, uint16 ammSpread, uint16 spreadBuffer, uint64 weight)
    public
    view
    returns (uint16[] memory bids, uint16[] memory asks, uint96[] memory subIds, uint64[] memory weights)
  {
    require(ammVol > (ammSpread + spreadBuffer), "spread + buffer > vol");

    bids = new uint16[](ACTIVE_SUBIDS);
    asks = new uint16[](ACTIVE_SUBIDS);
    subIds = new uint96[](ACTIVE_SUBIDS);
    weights = new uint64[](ACTIVE_SUBIDS);
    for (uint96 i; i < ACTIVE_SUBIDS; i++) {
      bids[i] = ammVol - ammSpread - spreadBuffer;
      asks[i] = ammVol + ammSpread + spreadBuffer;
      subIds[i] = i;
      weights[i] = weight;
    }
  }

  /**
   * @dev defender moves all excess capital to the attacked node
   */
  function _generateAttackResponse(uint16 spreadMultiple, uint64 weightMultiple)
    public view
    returns (uint16 newBid, uint16 newAsk, uint96 subId, uint64 weight)
  {
    /* see if any epoch is attacked */
    /* assume only 1 epoch attacked */
    bool isAttacked;
    uint96 attackedSubId;
    uint pendingLength;
    uint64 currWeight;
    uint16 currAsk;
    uint16 currBid;
    for (uint96 i; i < ACTIVE_SUBIDS; i++) {
      pendingLength = commitment.pendingLength();
      (currBid, currAsk, , , currWeight, ) = commitment.commitments(commitment.PENDING(), i, 1);

      if (pendingLength == 0) {
        isAttacked = true;
        attackedSubId = i;
        break;
      }
    }

    /* move deposit into node */
    if (isAttacked) {
      currWeight = weightMultiple * currWeight;
      uint16 oldSpread = (currAsk - currBid);
      uint16 buffer = (oldSpread / 2) * (spreadMultiple - 1);
      return (currBid - buffer, currAsk + buffer, attackedSubId, currWeight);
    }
    return (0, 0, 0, 0);
  }

  function _addListings() public {
    uint72[7] memory strikes = [1000e18, 1300e18, 1400e18, 1500e18, 1600e18, 1700e18, 2000e18];

    uint32[7] memory expiries = [1 weeks, 2 weeks, 4 weeks, 8 weeks, 12 weeks, 26 weeks, 52 weeks];
    for (uint s = 0; s < strikes.length; s++) {
      for (uint e = 0; e < expiries.length; e++) {
        optionAdapter.addListing(strikes[s], block.timestamp + expiries[e], true);
      }
    }
  }

  function _printCommits(uint96 subId, uint64 stakerId) public view {
    (,,,, uint64 commitWeight,) = commitment.commitments(commitment.COLLECTING(), subId, stakerId);
    console2.log("commit weight for subId 1: %s", commitWeight);
    
  }

  function _depositToNode(address staker, uint amount) public {
    _mintDai(staker, amount);
    // setup: not counting gas
    vm.startBroadcast(staker);

    dai.approve(address(commitment), type(uint).max);

    commitment.deposit(SafeCast.toUint128(amount)); // deposit $50k DAI

    vm.stopBroadcast();
  }

  function _deployCommitment() public {
    vm.startBroadcast(owner);
    // /* setup commitment contract */
    commitment = new CommitmentLinkedList(
      address(account), 
      address(dai),
      address(lending), 
      address(optionAdapter), 
      address(manager));
    vm.stopBroadcast();
  }

}
