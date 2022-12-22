// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../src/libraries/PCRMGrouping.sol";

contract PCRMGroupingTester {
  function updateForwards(PCRM.ExpiryHolding[] memory expiryHoldings)
    external
    pure
    returns (PCRM.ExpiryHolding[] memory)
  {
    PCRMGrouping.updateForwards(expiryHoldings);
    return expiryHoldings;
  }

  function findForwards(int calls, int puts, int forwards)
    external
    pure
    returns (int newCalls, int newPuts, int newForwards)
  {
    (newCalls, newPuts, newForwards) = PCRMGrouping.findForwards(calls, puts, forwards);
  }

  function findOrAddExpiry(PCRM.ExpiryHolding[] memory expiryHoldings, uint newExpiry, uint arrayLen, uint maxStrikes)
    external
    pure
    returns (uint, uint)
  {
    (uint expiryIndex, uint newArrayLen) = PCRMGrouping.findOrAddExpiry(expiryHoldings, newExpiry, arrayLen, maxStrikes);

    // had to inline error checks here since array modified via reference and getting stack overflow errors
    if (expiryHoldings[expiryIndex].expiry != newExpiry) {
      revert("invalid expiry entry");
    }

    if (newArrayLen > arrayLen && expiryIndex != arrayLen) {
      revert("invalid expiry index");
    }

    return (expiryIndex, newArrayLen);
  }

  function findOrAddStrike(PCRM.StrikeHolding[] memory strikeHoldings, uint newStrike, uint numStrikesHeld)
    external
    view
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
    (int newCalls, int newPuts, int newForwards) = tester.findForwards(0, 0, 0);
    assertEq(newCalls, 0);
    assertEq(newPuts, 0);
    assertEq(newForwards, 0);
  }

  function testFindingForwardsWhenNoForwards() public {
    (int newCalls, int newPuts, int newForwards) = tester.findForwards(10, 10, 0);
    assertEq(newCalls, 10);
    assertEq(newPuts, 10);
    assertEq(newForwards, 0);
  }

  function testFindingForwardsWhenLongForwardsPresent() public {
    (int newCalls, int newPuts, int newForwards) = tester.findForwards(10, -7, 0);
    assertEq(newCalls, 3);
    assertEq(newPuts, 0);
    assertEq(newForwards, 7);
  }

  function testFindingForwardsWhenShortForwardsPresent() public {
    (int newCalls, int newPuts, int newForwards) = tester.findForwards(-5, 10, 0);
    assertEq(newCalls, 0);
    assertEq(newPuts, 5);
    assertEq(newForwards, -5);
  }

  function testUpdateForwardsForAllHoldings() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();

    // check corrected filtering
    holdings = tester.updateForwards(holdings);
    assertEq(holdings[0].strikes[0].calls, 0);
    assertEq(holdings[0].strikes[0].puts, 0);
    assertEq(holdings[0].strikes[0].forwards, 11);
    assertEq(holdings[0].strikes[1].calls, 0);
    assertEq(holdings[0].strikes[1].puts, -10);
    assertEq(holdings[0].strikes[1].forwards, 5);
  }

  //////////////////////////////
  // Unique Elements in Array //
  //////////////////////////////

  function testFindOrAddExpiry() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint expiryIndex, uint newArrayLen) =
      tester.findOrAddExpiry(holdings, block.timestamp + 30 days, 2, pcrm.MAX_STRIKES());

    assertEq(expiryIndex, 2);
    assertEq(newArrayLen, 3);
  }

  function testAddExistingExpiry() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint expiryIndex, uint newArrayLen) = tester.findOrAddExpiry(holdings, holdings[0].expiry, 2, pcrm.MAX_STRIKES());

    assertEq(expiryIndex, 0);
    assertEq(newArrayLen, 2);
  }

  function testFindOrAddStrike() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(holdings[0].strikes, 1250e18, 2);

    assertEq(strikeIndex, 2);
    assertEq(newArrayLen, 3);
  }

  function testAddExistingStrike() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.findOrAddStrike(holdings[0].strikes, 10e18, 2);

    assertEq(strikeIndex, 0);
    assertEq(newArrayLen, 2);
  }

  //////////
  // Util //
  //////////
  function _getDefaultHoldings() public view returns (PCRM.ExpiryHolding[] memory) {
    // expiry 1
    PCRM.StrikeHolding[] memory strikeHoldings_1 = new PCRM.StrikeHolding[](pcrm.MAX_STRIKES());
    strikeHoldings_1[0] = PCRM.StrikeHolding({strike: 10e18, calls: 10, puts: -10, forwards: 1});
    strikeHoldings_1[1] = PCRM.StrikeHolding({strike: 15e18, calls: 0, puts: -10, forwards: 5});

    // expiry 2
    PCRM.StrikeHolding[] memory strikeHoldings_2 = new PCRM.StrikeHolding[](pcrm.MAX_STRIKES());
    strikeHoldings_2[0] = PCRM.StrikeHolding({strike: 20e18, calls: -3, puts: 5, forwards: 10});

    // all expiries
    PCRM.ExpiryHolding[] memory holdings = new PCRM.ExpiryHolding[](pcrm.MAX_EXPIRIES());
    holdings[0] = PCRM.ExpiryHolding({expiry: block.timestamp + 1 days, numStrikesHeld: 2, strikes: strikeHoldings_1});
    holdings[1] = PCRM.ExpiryHolding({expiry: block.timestamp + 7 days, numStrikesHeld: 1, strikes: strikeHoldings_2});

    return holdings;
  }
}
