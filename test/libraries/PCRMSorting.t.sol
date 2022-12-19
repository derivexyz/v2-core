// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/PCRMSorting.sol";

contract PCRMSortingTester {
  function filterForwards(PCRM.ExpiryHolding[] memory expiryHoldings) external pure {
    PCRMSorting.filterForwards(expiryHoldings);
  }

  function filterForwardsForStrike(int calls, int puts, int forwards) external pure returns (
    int newCalls, int newPuts, int newForwards
  ) {
    (newCalls, newPuts, newForwards) = PCRMSorting.filterForwardsForStrike(calls, puts, forwards);
  }
}

contract PCRMSortingTest is Test {
  PCRMSortingTester tester;

  function setUp() public {
    tester = new PCRMSortingTester();
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
    // expiry 1
    PCRM.StrikeHolding[] memory strikeHoldings_1 = new PCRM.StrikeHolding[](2);
    strikeHoldings_1[0] = PCRM.StrikeHolding({
      strike: 10e18,
      calls: 10,
      puts: -10,
      forwards: 1
    });
    strikeHoldings_1[1] = PCRM.StrikeHolding({
      strike: 10e18,
      calls: 0,
      puts: -10,
      forwards: 5
    });

    // expiry 2
    PCRM.StrikeHolding[] memory strikeHoldings_2 = new PCRM.StrikeHolding[](1);
    strikeHoldings_2[0] = PCRM.StrikeHolding({
      strike: 10e18,
      calls: -3,
      puts: 5,
      forwards: 10
    });

    // all expiries
    PCRM.ExpiryHolding[] memory holdings = new PCRM.ExpiryHolding[](2);
    holdings[0] = PCRM.ExpiryHolding({
      expiry: block.timestamp + 1 days,
      strikes: strikeHoldings_1
    });
    holdings[1] = PCRM.ExpiryHolding({
      expiry: block.timestamp + 7 days,
      strikes: strikeHoldings_2
    });

    // check corrected filtering
    tester.filterForwards(holdings);
    assertEq(holdings[0].strikes[0].calls, 0);
    assertEq(holdings[0].strikes[0].puts, 0);
    assertEq(holdings[0].strikes[0].forwards, 11);
    assertEq(holdings[0].strikes[0].calls, 0);
    assertEq(holdings[0].strikes[0].puts, -10);
    assertEq(holdings[0].strikes[0].forwards, 5);

  }
}