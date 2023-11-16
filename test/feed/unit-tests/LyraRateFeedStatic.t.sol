// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../src/feeds/LyraRateFeedStatic.sol";

import "forge-std/Test.sol";

contract UNIT_LyraRateFeed is Test {
  LyraRateFeedStatic feed;

  function setUp() public {
    feed = new LyraRateFeedStatic();
  }

  function testSetRate() public {
    int64 _rate = 0.04e18;
    uint64 _confidence = 1e18;
    feed.setRate(_rate, _confidence);

    (int rate, uint confidence) = feed.getInterestRate(0);
    assertEq(rate, _rate);
    assertEq(confidence, _confidence);

    feed.setRate(-_rate, _confidence);
    (rate,) = feed.getInterestRate(0);
    assertEq(rate, -_rate);
  }

  function testCannotSetRateOutOfRange() public {
    int64 _rate = 1.1e18;
    uint64 _confidence = 1e18;
    vm.expectRevert(LyraRateFeedStatic.LRFS_StaticRateOutOfRange.selector);
    feed.setRate(_rate, _confidence);
  }
}
