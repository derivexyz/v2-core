//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./MockAsset.sol";

import "src/interfaces/IPerpAsset.sol";

contract MockPerp is MockAsset, IPerpAsset {
  constructor(IAccounts account) MockAsset(IERC20(address(0)), account, true) {}

  function updateFundingRate() external {}

  function applyFundingOnAccount(uint accountId) external {}

  /**
   * @dev manager-only function to clear pnl and funding during settlement
   */
  function settleRealizedPNLAndFunding(uint accountId) external returns (int netCash) {}
}
