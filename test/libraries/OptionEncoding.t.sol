// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/OptionEncoding.sol";

contract OptionEncodingTester {
  function toSubId(uint expiry, uint strike, bool isCall) external pure returns (uint96) {
    uint96 subId = OptionEncoding.toSubId(expiry, strike, isCall);
    return subId;
  }

  function fromSubId(uint96 subId) external pure returns (uint, uint, bool) {
    (uint expiry, uint strike, bool isCall) = OptionEncoding.fromSubId(subId);
    return (expiry, strike, isCall);
  }
}

contract OptionEncodingTest is Test {
  OptionEncodingTester tester;

  function setUp() public {
    tester = new OptionEncodingTester();
  }

  function testSeveralExamples() public {
    // 6 mo, $100k strike, call
    uint expiry = block.timestamp + 60 days;
    uint strike = 100_000e18;
    bool isCall = true;
    uint96 subId = tester.toSubId(expiry, strike, isCall);
    _assertCorrectSubId(subId, expiry, strike, isCall);

    // 1 mo, $1k strike, put
    expiry = block.timestamp + 30 days;
    strike = 1000e18;
    isCall = false;
    subId = tester.toSubId(expiry, strike, isCall);
    _assertCorrectSubId(subId, expiry, strike, isCall);

    // 27 day : 3 hour : 45 sec, $85.4321 strike, call
    expiry = block.timestamp + 27 days + 3 hours + 45 seconds;
    strike = 85e18 + 4321e14;
    isCall = true;
    subId = tester.toSubId(expiry, strike, isCall);
    _assertCorrectSubId(subId, expiry, strike, isCall);

    // 1mo, zero strike, call
    expiry = block.timestamp + 30 days;
    strike = 0;
    isCall = true;
    subId = tester.toSubId(expiry, strike, isCall);
    _assertCorrectSubId(subId, expiry, strike, isCall);
  }

  function testFuzzEncoding(uint expiry, uint strike, bool isCall) public {
    vm.assume(expiry < (2 ** 32) - 1);
    vm.assume(strike < (2 ** 63) - 1);
    vm.assume(strike % 1e10 == 0);

    uint96 subId = tester.toSubId(expiry, strike, isCall);
    _assertCorrectSubId(subId, expiry, strike, isCall);
  }

  function testExpiryTooLarge() public {
    uint expiry = 7288361592000; // epoch time for Year 2200
    vm.expectRevert(abi.encodeWithSelector(OptionEncoding.OE_ExpiryTooLarge.selector, expiry));
    tester.toSubId(expiry, 1e18, true);
  }

  function testStrikeTooLarge() public {
    // (1) add 10 decimal places (2) > uint63.max but remove decimal points
    uint strike = 100_000_000_000e8 * 1e10;
    vm.expectRevert(abi.encodeWithSelector(OptionEncoding.OE_StrikeTooLarge.selector, strike / 1e10));
    tester.toSubId(1 days, strike, true);
  }

  function testStrikeTooGranular() public {
    uint strike = 100.00000000001e18; // more than 10 decimal point precision
    vm.expectRevert(abi.encodeWithSelector(OptionEncoding.OE_StrikeTooGranular.selector, strike));
    tester.toSubId(1 days, strike, true);
  }

  function _assertCorrectSubId(uint96 subId, uint expectedExpiry, uint expectedStrike, bool expectedIsCall) internal {
    (uint expiry, uint strike, bool isCall) = tester.fromSubId(subId);
    assertEq(expiry, expectedExpiry);
    assertEq(strike, expectedStrike);
    assertEq(isCall, expectedIsCall);
  }
}
