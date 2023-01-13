// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../src/libraries/PCRMGrouping.sol";

contract PCRMGroupingTester {
  function updateForwards(PCRM.StrikeHolding memory strikeHolding) external pure returns (PCRM.StrikeHolding memory) {
    PCRMGrouping.updateForwards(strikeHolding);
    return strikeHolding;
  }

  function findForwards(int calls, int puts) external pure returns (int newForwards) {
    newForwards = PCRMGrouping.findForwards(calls, puts);
  }

  function findOrAddStrike(PCRM.StrikeHolding[] memory strikeHoldings, uint newStrike, uint numStrikesHeld)
    external
    pure
    returns (uint, uint)
  {
    (uint strikeIndex, uint newArrayLen) = PCRMGrouping.findOrAddStrike(strikeHoldings, newStrike, numStrikesHeld);

    // had to inline error checks here since array modified via reference and getting stack overflow errors
    if (strikeHoldings[strikeIndex].strike != newStrike) {
      revert("invalid strike price");
    }

    if (newArrayLen > numStrikesHeld && strikeIndex != numStrikesHeld) {
      revert("invalid strike index");
    }

    return (strikeIndex, newArrayLen);
  }
}

contract PCRMGroupingTest is Test {
  PCRMGroupingTester tester;
  PCRM pcrm;

  function setUp() public {
    tester = new PCRMGroupingTester();
    pcrm = new PCRM(
      address(0), address(0), address(0), address(0), address(0)
    );
  }

  ///////////////////////
  // Forward Filtering //
  ///////////////////////

  function testFindingForwardsWhenZeroBalance() public {
    int newForwards = tester.findForwards(0, 0);
    assertEq(newForwards, 0);
  }

  function testFindingForwardsWhenNoForwards() public {
    int newForwards = tester.findForwards(10, 10);
    assertEq(newForwards, 0);
  }

  function testFindingForwardsWhenLongForwardsPresent() public {
    int newForwards = tester.findForwards(10, -7);
    assertEq(newForwards, 7);
  }

  function testFindingForwardsWhenShortForwardsPresent() public {
    int newForwards = tester.findForwards(-5, 10);
    assertEq(newForwards, -5);
  }

  function testUpdateForwardsForStrike() public {
    PCRM.ExpiryHolding memory holdings = _getDefaultHoldings();

    // check corrected filtering
    PCRM.StrikeHolding memory strike_0 = tester.updateForwards(holdings.strikes[0]);
    assertEq(strike_0.calls, 0);
    assertEq(strike_0.puts, 0);
    assertEq(strike_0.forwards, 11);

    PCRM.StrikeHolding memory strike_1 = tester.updateForwards(holdings.strikes[1]);
    assertEq(strike_1.calls, 0);
    assertEq(strike_1.puts, -10);
    assertEq(strike_1.forwards, 5);
  }

  //////////////////////////////
  // Unique Elements in Array //
  //////////////////////////////


  function testFindOrAddStrike() public {
    PCRM.ExpiryHolding memory holdings = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(holdings.strikes, 1250e18, 2);

    assertEq(strikeIndex, 2);
    assertEq(newArrayLen, 3);
  }

  function testAddExistingStrike() public {
    PCRM.ExpiryHolding memory holdings = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(holdings.strikes, 10e18, 2);

    assertEq(strikeIndex, 0);
    assertEq(newArrayLen, 2);
  }

  //////////
  // Util //
  //////////
  function _getDefaultHoldings() public view returns (PCRM.ExpiryHolding memory) {
    PCRM.StrikeHolding[] memory strikes = new PCRM.StrikeHolding[](pcrm.MAX_STRIKES());
    // strike 1
    strikes[0] = PCRM.StrikeHolding({strike: 10e18, calls: 10, puts: -10, forwards: 1});
    
    // strike 2
    strikes[1] = PCRM.StrikeHolding({strike: 15e18, calls: 0, puts: -10, forwards: 5});

    // all expiries
    PCRM.ExpiryHolding memory holdings = PCRM.ExpiryHolding({
      expiry: block.timestamp + 7 days,
      numStrikesHeld: 2,
      strikes: strikes
    });

    return holdings;
  }
}
