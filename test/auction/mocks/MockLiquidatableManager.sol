// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "test/shared/mocks/MockManager.sol";

import "src/interfaces/ILiquidatableManager.sol";

contract MockLiquidatableManager is MockManager, ILiquidatableManager {
  mapping(uint tradeId => mapping(uint account => uint fee)) mockFeeCharged;
  mapping(uint => mapping(bool => int)) mockMargin;

  mapping(uint => int) mockMarkToMarket;

  constructor(address account_) MockManager(account_) {}

  function setMockMargin(uint accountId, bool isInitial, int margin) external {
    mockMargin[accountId][isInitial] = margin;
  }

  function setMockFeeCharged(uint tradeId, uint account, uint fee) external {
    mockFeeCharged[tradeId][account] = fee;
  }

  function feeCharged(uint tradeId, uint account) external view returns (uint) {
    return mockFeeCharged[tradeId][account];
  }

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint totalPortion, uint cashAmount) external {
    // do nothing
  }

  function getMargin(uint accountId, bool isInitial) external view override returns (int) {
    return mockMargin[accountId][isInitial];
  }

  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId) external view returns (int, int) {
    return (mockMargin[accountId][isInitial], mockMarkToMarket[accountId]);
  }

  function getMarkToMarket(uint accountId) external view returns (int) {
    return mockMarkToMarket[accountId];
  }

  function setMarkToMarket(uint accountId, int markToMarket) external {
    mockMarkToMarket[accountId] = markToMarket;
  }

  function settlePerpsWithIndex(IPerpAsset _perp, uint accountId) external {}

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public override {}
}
