// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../src/libraries/PCRMSorting.sol";

contract PCRMSortingTester {
  function filterForwards(PCRM.ExpiryHolding[] memory expiryHoldings)
    external
    pure
    returns (PCRM.ExpiryHolding[] memory)
  {
    PCRMSorting.filterForwards(expiryHoldings);
    return expiryHoldings;
  }

  function filterForwardsForStrike(int calls, int puts, int forwards)
    external
    pure
    returns (int newCalls, int newPuts, int newForwards)
  {
    (newCalls, newPuts, newForwards) = PCRMSorting.filterForwardsForStrike(calls, puts, forwards);
  }

  function addUniqueExpiry(PCRM.ExpiryHolding[] memory expiryHoldings, uint newExpiry, uint arrayLen, uint maxStrikes)
    external
    pure
    returns (uint, uint)
  {
    (uint expiryIndex, uint newArrayLen) = PCRMSorting.addUniqueExpiry(expiryHoldings, newExpiry, arrayLen, maxStrikes);

    // had to inline error checks here since array modified via reference and getting stack overflow errors
    if (expiryHoldings[expiryIndex].expiry != newExpiry) {
      revert("invalid expiry entry");
    }

    if (newArrayLen > arrayLen && expiryIndex != arrayLen) {
      revert("invalid expiry index");
    }

    return (expiryIndex, newArrayLen);
  }

  function addUniqueStrike(PCRM.StrikeHolding[] memory strikeHoldings, uint newStrike, uint numStrikesHeld)
    external
    pure
    returns (uint, uint)
  {
    (uint strikeIndex, uint newArrayLen) = PCRMSorting.addUniqueStrike(strikeHoldings, newStrike, numStrikesHeld);

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

contract PCRMSortingTest is Test {
  PCRMSortingTester tester;
  PCRM pcrm;

  function setUp() public {
    tester = new PCRMSortingTester();
    pcrm = new PCRM(
      address(0), address(0), address(0), address(0), address(0)
    );
  }

  ///////////////////////
  // Forward Filtering //
  ///////////////////////

  function testStrikeFilteringForZeroBalance() public {
    (int newCalls, int newPuts, int newForwards) = tester.filterForwardsForStrike(0, 0, 0);
    assertEq(newCalls, 0);
    assertEq(newPuts, 0);
    assertEq(newForwards, 0);
  }

  function testStrikeFilteringForNoForwards() public {
    (int newCalls, int newPuts, int newForwards) = tester.filterForwardsForStrike(10, 10, 0);
    assertEq(newCalls, 10);
    assertEq(newPuts, 10);
    assertEq(newForwards, 0);
  }

  function testStrikeFilteringWhenLongForwardsPresent() public {
    (int newCalls, int newPuts, int newForwards) = tester.filterForwardsForStrike(10, -7, 0);
    assertEq(newCalls, 3);
    assertEq(newPuts, 0);
    assertEq(newForwards, 7);
  }

  function testStrikeFilteringWhenShortForwardsPresent() public {
    (int newCalls, int newPuts, int newForwards) = tester.filterForwardsForStrike(-5, 10, 0);
    assertEq(newCalls, 0);
    assertEq(newPuts, 5);
    assertEq(newForwards, -5);
  }

  function testFullFiltering() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();

    // check corrected filtering
    holdings = tester.filterForwards(holdings);
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

  function testAddUniqueExpiry() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint expiryIndex, uint newArrayLen) =
      tester.addUniqueExpiry(holdings, block.timestamp + 30 days, 2, pcrm.MAX_STRIKES());

    assertEq(expiryIndex, 2);
    assertEq(newArrayLen, 3);
  }

  function testAddExistingExpiry() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint expiryIndex, uint newArrayLen) = tester.addUniqueExpiry(holdings, holdings[0].expiry, 2, pcrm.MAX_STRIKES());

    assertEq(expiryIndex, 0);
    assertEq(newArrayLen, 2);
  }

  function testAddUniqueStrike() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.addUniqueStrike(holdings[0].strikes, 1250e18, 2);

    assertEq(strikeIndex, 2);
    assertEq(newArrayLen, 3);
  }

  function testAddExistingStrike() public {
    PCRM.ExpiryHolding[] memory holdings = _getDefaultHoldings();
    (uint strikeIndex, uint newArrayLen) = tester.addUniqueStrike(holdings[0].strikes, 10e18, 2);

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
