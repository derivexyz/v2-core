// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../../src/assets/Lending.sol";
import "../../../../src/Account.sol";

contract UNIT_LendingHook is Test {
  Lending lending;
  function setUp() public {
    Account account = new Account();
    lending = new Lending(account);
  }

  /**
   * ==========================================================
   * tests for call flow rom Manager => Account.adjustBalance() |
   * ========================================================== *
   */

  
}
