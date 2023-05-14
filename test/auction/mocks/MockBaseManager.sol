// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "test/shared/mocks/MockManager.sol";

import "src/interfaces/IBaseManager.sol";

contract MockBaseManager is MockManager, IBaseManager {
  mapping(uint tradeId => mapping(uint account => uint fee)) mockFeeCharged;

  constructor(address account_) MockManager(account_) {}

  function setMockFeeCharged(uint tradeId, uint account, uint fee) external {
    mockFeeCharged[tradeId][account] = fee;
  }

  function feeCharged(uint tradeId, uint account) external view returns (uint) {
    return mockFeeCharged[tradeId][account];
  }

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee) external {
    // do nothing
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public override {}
}
