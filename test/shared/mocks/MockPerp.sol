//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./MockAsset.sol";

import "src/interfaces/IPerpAsset.sol";

contract MockPerp is MockAsset, IPerpAsset {
  constructor(IAccounts account) MockAsset(IERC20(address(0)), account, true) {}

  function updateFundingRate() external {}

  function applyFundingOnAccount(uint accountId) external {}

  function settleRealizedPNLAndFunding(uint accountId) external returns (int netCash) {}

  function assetType() external pure override(IAsset, MockAsset) returns (AssetType) {
    return AssetType.Perpetual;
  }

  /**
   * @dev return underlying asset id, (e.g.: ETH = 0, BTC = 1)
   */
  function underlyingId() external pure override(IAsset, MockAsset) returns (uint) {
    return 1;
  }
}
