// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../../../../src/assets/Option.sol";
import "../../../../src/Accounts.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";

/**
 * @dev testing open interest before and after
 * asset transfers
 * single side adjustments
 */
contract UNIT_OptionAssetOITest is Test {
  Option option;
  MockManager manager;
  Accounts account;

  ChainlinkSpotFeeds spotFeeds;
  MockV3Aggregator aggregator;

  int tradeAmount = 100e18;
  uint accountPos; // balance: 100
  uint accountNeg; // balance: -100
  uint accountEmpty; // balance: 0

  uint expiry = block.timestamp + 2 weeks;
  uint strike = 1000e18;
  uint callId;
  uint putId;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
    manager = new MockManager(address(account));

    uint feedId = _setupFeeds();
    option = new Option(account, address(spotFeeds), feedId);

    callId = option.getSubId(expiry, strike, true);
    putId = option.getSubId(expiry, strike, false);

    accountPos = account.createAccount(address(this), manager);
    accountNeg = account.createAccount(address(this), manager);
    // init these 2 accounts with positive and negative balance
    _transfer(accountNeg, accountPos, tradeAmount);

    accountEmpty = account.createAccount(address(this), manager);
  }

  function testCanSetSettlementPrice() external {
    // First confirm that the settlement price hasn't been set for callId
    assertEq(option.settlementPrices(callId), 0);

    // Fast forward to expiry and update feed
    (uint expiry,,) = option.getOptionDetails(uint96(callId));
    vm.warp(expiry);
    _updateFeed(aggregator, 2, 1200e18, 2);

    // Lock in settlment price
    option.setSettlementPrice(callId);

    // Assert settled price same as feed
    (, int answer,,,) = aggregator.latestRoundData();
    assertEq(option.settlementPrices(expiry), uint(answer));
  }

  function testCannotOptionNotExpired() external {
    (uint expiry,,) = option.getOptionDetails(uint96(callId));

    // Should revert because we have not reached expiry time
    vm.expectRevert(abi.encodeWithSelector(ISettlementFeed.NotExpired.selector, expiry, block.timestamp));
    option.setSettlementPrice(callId);
  }

  function testCannotSettlePriceAlreadySet() external {
    // First confirm that the settlement price hasn't been set for callId
    assertEq(option.settlementPrices(callId), 0);

    // Fast forward to expiry and update feed
    (uint expiry,,) = option.getOptionDetails(uint96(callId));
    vm.warp(expiry);
    _updateFeed(aggregator, 2, 1200e18, 2);

    // Lock in settlment price for callId
    option.setSettlementPrice(callId);

    // Assert settled price same as feed
    (, int answer,,,) = aggregator.latestRoundData();
    assertEq(option.settlementPrices(expiry), uint(answer));

    // Revert for putId because it has the same expiry
    vm.expectRevert(abi.encodeWithSelector(ISettlementFeed.SettlementPriceAlreadySet.selector, expiry, uint(answer)));
    option.setSettlementPrice(putId);
  }

  function testCalcSettlementValueITMCall() external {
    (uint expiry, uint strike,) = option.getOptionDetails(uint96(callId));

    // Lock in settlment price for callId at expiry above strike
    vm.warp(expiry);
    int spotPrice = int(strike) + 200e18;
    _updateFeed(aggregator, 2, spotPrice, 2);
    option.setSettlementPrice(callId);

    (int payout, bool priceSettled) = option.calcSettlementValue(callId, 1e18);

    // Call should profit 200
    assertEq(uint(payout), uint(spotPrice) - strike);
  }

  function testCalcSettlementValueOTMCall() external {
    (uint expiry, uint strike,) = option.getOptionDetails(uint96(callId));

    // Lock in settlment price for callId at expiry below strike
    vm.warp(expiry);
    int spotPrice = int(strike) - 200e18;
    _updateFeed(aggregator, 2, spotPrice, 2);
    option.setSettlementPrice(callId);

    (int payout, bool priceSettled) = option.calcSettlementValue(callId, 1e18);

    // Call should be worthless
    assertEq(uint(payout), 0);
  }

  function testCalcSettlementValueITMPut() external {
    (uint expiry, uint strike,) = option.getOptionDetails(uint96(putId));

    // Lock in settlment price for putId at expiry below strike
    vm.warp(expiry);
    int spotPrice = int(strike) - 200e18;
    _updateFeed(aggregator, 2, spotPrice, 2);
    option.setSettlementPrice(putId);

    (int payout, bool priceSettled) = option.calcSettlementValue(putId, 1e18);

    // Put should profit 200
    assertEq(uint(payout), strike - uint(spotPrice));
  }

  function testCalcSettlementValueOTMPut() external {
    (uint expiry, uint strike,) = option.getOptionDetails(uint96(putId));

    // Lock in settlment price for putId at expiry above strike
    vm.warp(expiry);
    int spotPrice = int(strike) + 200e18;
    _updateFeed(aggregator, 2, spotPrice, 2);
    option.setSettlementPrice(putId);

    (int payout, bool priceSettled) = option.calcSettlementValue(putId, 1e18);

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

  function _setupFeeds() public returns (uint) {
    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    uint feedId = spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);
    aggregator.updateRoundData(1, 1000e18, block.timestamp, block.timestamp, 1);
    return feedId;
  }

  function _updateFeed(MockV3Aggregator aggregator, uint80 roundId, int spotPrice, uint80 answeredInRound) internal {
    aggregator.updateRoundData(roundId, spotPrice, block.timestamp, block.timestamp, answeredInRound);
  }

  /// @dev util function to transfer
  function _transfer(uint from, uint to, int amount) internal {
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: from,
      toAcc: to,
      asset: option,
      subId: callId,
      amount: amount,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }
}
