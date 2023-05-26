//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";

import "./MockAsset.sol";

import "src/interfaces/IPerpAsset.sol";

contract MockPerp is MockAsset, IPerpAsset {
  mapping(uint => int) mockedFunding;
  mapping(uint => int) mockedPNL;

  mapping(uint => uint) public openInterest;

  ///@dev SubId => tradeId => open interest snapshot
  mapping(uint => mapping(uint => OISnapshot)) public openInterestBeforeTrade;

  mapping(IManager => uint) public mockedTotalPosition;

  mapping(IManager => uint) public mockedTotalPositionCap;

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

  function setMockedOI(uint _subId, uint _oi) external {
    openInterest[_subId] = _oi;
  }

  function setMockedOISnapshotBeforeTrade(uint _subId, uint _tradeId, uint _oi) external {
    openInterestBeforeTrade[_subId][_tradeId] = OISnapshot(true, uint240(_oi));
  }

  function totalPosition(IManager manager) external view returns (uint) {
    return mockedTotalPosition[manager];
  }

  function totalPositionCap(IManager manager) external view returns (uint) {
    return mockedTotalPositionCap[manager];
  }

  function setTotalPosition(IManager manager, uint position) external {
    mockedTotalPosition[manager] = position;
  }

  function setTotalPositionCap(IManager manager, uint positionCap) external {
    mockedTotalPositionCap[manager] = positionCap;
  }
}
