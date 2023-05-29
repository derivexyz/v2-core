// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "test/shared/mocks/MockManager.sol";

import "src/interfaces/ILiquidatableManager.sol";
import "src/interfaces/IDutchAuction.sol";

contract MockLiquidatableManager is MockManager, ILiquidatableManager {
  mapping(uint tradeId => mapping(uint account => uint fee)) mockFeeCharged;
  mapping(uint account => mapping(bool isInitial => mapping(uint scenario => int margin))) mockMargin;

  mapping(uint => int) mockMarkToMarket;

  uint public feePaid;

  constructor(address account_) MockManager(account_) {}

  function setMockMargin(uint accountId, bool isInitial, uint scenario, int margin) external {
    mockMargin[accountId][isInitial][scenario] = margin;
  }

  function setMockFeeCharged(uint tradeId, uint accountId, uint fee) external {
    mockFeeCharged[tradeId][accountId] = fee;
  }

  function feeCharged(uint tradeId, uint accountId) external view returns (uint) {
    return mockFeeCharged[tradeId][accountId];
  }

  function settleInterest(uint accountId) external {}

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount) external {
    // do nothing
  }

  function payLiquidationFee(uint, uint, uint cashAmount) external {
    feePaid += cashAmount;
  }

  function getMargin(uint, bool) external pure override returns (int) {
    return 0;
  }

  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId) external view returns (int, int) {
    return (mockMargin[accountId][isInitial][scenarioId], mockMarkToMarket[accountId]);
  }

  function getMarkToMarket(uint accountId) external view returns (int) {
    return mockMarkToMarket[accountId];
  }

  function setMarkToMarket(uint accountId, int markToMarket) external {
    mockMarkToMarket[accountId] = markToMarket;
  }

  function settlePerpsWithIndex(IPerpAsset _perp, uint accountId) external {}

  function settleOptions(IOption _option, uint accountId) external {}

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public override {}

  function forceAuction(IDutchAuction auction, uint accountId, uint scenario) external {
    auction.startForcedAuction(accountId, scenario);
  }
}
