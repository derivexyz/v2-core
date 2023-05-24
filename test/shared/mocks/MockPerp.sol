//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./MockAsset.sol";

import "src/interfaces/IPerpAsset.sol";

contract MockPerp is MockAsset, IPerpAsset {
  mapping(uint => int) mockedFunding;
  mapping(uint => int) mockedPNL;

  constructor(IAccounts account) MockAsset(IERC20(address(0)), account, true) {}

  function updateFundingRate() external {}

  function applyFundingOnAccount(uint accountId) external {}

  function settleRealizedPNLAndFunding(uint accountId) external view returns (int, int) {
    return (mockedFunding[accountId], mockedPNL[accountId]);
  }

  function mockAccountPnlAndFunding(uint accountId, int funding, int pnl) external {
    mockedFunding[accountId] = funding;
    mockedPNL[accountId] = pnl;
  }

  function getUnsettledAndUnrealizedCash(uint accountId) external view returns (int totalCash) {
    return mockedFunding[accountId] + mockedPNL[accountId];
  }

  function getIndexPrice() external view returns (uint) {}

  function realizePNLWithIndex(uint account) external {}
}
