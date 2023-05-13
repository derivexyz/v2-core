// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../../../../src/assets/Option.sol";
import "../../../../src/Accounts.sol";
import "test/shared/mocks/MockFeeds.sol";

/**
 * @dev Tests functions related to OptionAsset settlements
 * setSettlementPrice
 * calcSettlementValue
 */
contract UNIT_OptionAssetSettlementsTest is Test {
  Option option;
  Accounts account;

  MockFeeds feed;

  int public constant BIG_PRICE = 1e42;
  uint setExpiry = block.timestamp + 2 weeks;
  uint strike = 1000e18;
  uint callId;
  uint putId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    feed = new MockFeeds();
    option = new Option(account, address(feed));

    callId = option.getSubId(setExpiry, strike, true);
    putId = option.getSubId(setExpiry, strike, false);
  }

  function testCalcSettlementValueITMCall() external {
    (uint expiry,,) = option.getOptionDetails(uint96(callId));

    // Lock in settlement price for callId at expiry above strike
    vm.warp(expiry);
    uint spotPrice = uint(strike) + 200e18;
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(callId, 1e18);

    // Call should profit 200
    assertEq(uint(payout), 200e18);
  }

  function testCalcSettlementValueOTMCall() external {
    (uint expiry,,) = option.getOptionDetails(uint96(callId));

    // Lock in settlement price for callId at expiry below strike
    vm.warp(expiry);
    uint spotPrice = uint(strike) - 200e18;
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(callId, 1e18);

    // Call should be worthless
    assertEq(uint(payout), 0);
  }

  function testCalcSettlementValueITMPut() external {
    (uint expiry,,) = option.getOptionDetails(uint96(putId));

    // Lock in settlement price for putId at expiry below strike
    vm.warp(expiry);
    uint spotPrice = uint(strike) - 200e18;
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(putId, 1e18);

    // Put should profit 200
    assertEq(uint(payout), 200e18);
  }

  function testCalcSettlementValueOTMPut() external {
    (uint expiry,,) = option.getOptionDetails(uint96(putId));

    // Lock in settlement price for putId at expiry above strike
    vm.warp(expiry);
    uint spotPrice = uint(strike) + 200e18;
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(putId, 1e18);

    // Put should profit 200
    assertEq(uint(payout), 0);
  }

  function testCannotCalcSettlementValuePriceNotSet() external {
    // Cannot set settlement price because have not reached expiry
    (uint expiry,,) = option.getOptionDetails(uint96(callId));
    assertGt(expiry, block.timestamp);
    (int payout, bool priceSettled) = option.calcSettlementValue(callId, 1e18);

    // Return 0, false because settlement price has not been set
    assertEq(payout, 0);
    assertEq(priceSettled, false);
  }

  /* --------------------- *
   |      Fuzz Tests       *
   * --------------------- */

  function testFuzzITMCall(int priceDiff) external {
    vm.assume(priceDiff >= 0 && priceDiff <= BIG_PRICE);
    (uint expiry,,) = option.getOptionDetails(uint96(callId));

    // Lock in settlement price for callId at expiry above strike
    vm.warp(expiry);
    uint spotPrice = uint(int(strike) + priceDiff);
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(callId, 1e18);

    // Call should payout spot - strike
    assertEq(uint(payout), uint(spotPrice) - strike);
  }

  function testFuzzOTMCall(int priceDiff) external {
    vm.assume(priceDiff >= 0 && priceDiff <= int(strike));
    (uint expiry,,) = option.getOptionDetails(uint96(callId));

    // Lock in settlement price for callId at expiry below strike
    vm.warp(expiry);
    uint spotPrice = uint(int(strike) - priceDiff);
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(callId, 1e18);

    // Call should be worthless
    assertEq(uint(payout), 0);
  }

  function testFuzzITMPut(int priceDiff) external {
    vm.assume(priceDiff >= 0 && priceDiff < int(strike));
    (uint expiry,,) = option.getOptionDetails(uint96(putId));

    // Lock in settlement price for putId at expiry below strike
    vm.warp(expiry);
    uint spotPrice = uint(int(strike) - priceDiff);
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(putId, 1e18);

    // Put should be payout spot - strike
    assertEq(uint(payout), strike - uint(spotPrice));
  }

  function testFuzzOTMPut(int priceDiff) external {
    vm.assume(priceDiff >= 0 && priceDiff <= BIG_PRICE);
    (uint expiry,,) = option.getOptionDetails(uint96(putId));

    // Lock in settlement price for putId at expiry above strike
    vm.warp(expiry);
    uint spotPrice = uint(int(strike) + priceDiff);
    feed.setForwardPrice(expiry, spotPrice, 1e18);

    (int payout,) = option.calcSettlementValue(putId, 1e18);

    // Put should be worthless
    assertEq(uint(payout), 0);
  }
}
