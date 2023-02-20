// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "test/shared/mocks/MockManager.sol";

contract MockPCRMManager is MockManager {
  constructor(address account_) MockManager(account_) {}

  uint public initialStaticCashOffset = 0;

  function setStaticOffset(uint offset) external {
    initialStaticCashOffset = offset;
  }

  function portfolioDiscountParams() external view returns (uint, uint, uint, uint) {
    return (0, 0, initialStaticCashOffset, 0);
  }
}
