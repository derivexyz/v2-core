// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../src/libraries/PCRMGrouping.sol";

contract PCRMGroupingTester {
  function updateForwards(BaseManager.Strike memory strike) external pure returns (BaseManager.Strike memory) {
    PCRMGrouping.updateForwards(strike);
    return strike;
  }

  function findForwards(int calls, int puts) external pure returns (int newForwards) {
    newForwards = PCRMGrouping.findForwards(calls, puts);
  }

  function findOrAddStrike(BaseManager.Strike[] memory strikes, uint newStrike, uint numStrikesHeld)
    external
    pure
    returns (uint, uint)
  {
    (uint strikeIndex, uint newArrayLen) = PCRMGrouping.findOrAddStrike(strikes, newStrike, numStrikesHeld);

    // had to inline error checks here since array modified via reference and getting stack overflow errors
    if (strikes[strikeIndex].strike != newStrike) {
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

  function setUp() public {
    tester = new PCRMGroupingTester();
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
    BaseManager.Portfolio memory portfolio = _getDefaultHoldings();

    // check corrected filtering
    BaseManager.Strike memory strike_0 = tester.updateForwards(portfolio.strikes[0]);
    assertEq(strike_0.calls, 0);
    assertEq(strike_0.puts, 0);
    assertEq(strike_0.forwards, 11);

    BaseManager.Strike memory strike_1 = tester.updateForwards(portfolio.strikes[1]);
    assertEq(strike_1.calls, 0);
    assertEq(strike_1.puts, -10);
    assertEq(strike_1.forwards, 5);
  }

  //////////////////////////////
  // Unique Elements in Array //
  //////////////////////////////

  function testFindOrAddStrike() public {
    BaseManager.Portfolio memory portfolio = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(portfolio.strikes, 1250e18, 2);

    assertEq(strikeIndex, 2);
    assertEq(newArrayLen, 3);
  }

  function testAddExistingStrike() public {
    BaseManager.Portfolio memory portfolio = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(portfolio.strikes, 10e18, 2);

    assertEq(strikeIndex, 0);
    assertEq(newArrayLen, 2);
  }

  //////////
  // Util //
  //////////
  function _getDefaultHoldings() public view returns (BaseManager.Portfolio memory) {
    // Hardcode max strike = 64
    uint MAX_STRIKE = 64;
    BaseManager.Strike[] memory strikes = new BaseManager.Strike[](MAX_STRIKE);
    // strike 1
    strikes[0] = BaseManager.Strike({strike: 10e18, calls: 10, puts: -10, forwards: 1});

    // strike 2
    strikes[1] = BaseManager.Strike({strike: 15e18, calls: 0, puts: -10, forwards: 5});

    // all expiries
    BaseManager.Portfolio memory portfolio =
      BaseManager.Portfolio({cash: 0, expiry: block.timestamp + 7 days, numStrikesHeld: 2, strikes: strikes});

    return portfolio;
  }
}
