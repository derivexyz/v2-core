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

  function testStrikeFilteringForZeroBalance() public {
    (int newCalls, int newPuts, int newForwards) = tester.filterForwardsForStrike(0, 0, 0);
    assertEq(newCalls, 0);
    assertEq(newPuts, 0);
    assertEq(newForwards, 0);
  }
}