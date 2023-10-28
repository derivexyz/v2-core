//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";

import {MockAsset} from "./MockAsset.sol";
import {MockPositionTracking} from "./MockPositionTracking.sol";
import {MockGlobalSubIdOITracking} from "./MockGlobalSubIdOITracking.sol";

import {IPerpAsset} from "../../../src/interfaces/IPerpAsset.sol";
import {ISubAccounts} from "../../../src/interfaces/ISubAccounts.sol";

contract MockPerp is MockAsset, MockPositionTracking, MockGlobalSubIdOITracking, IPerpAsset {
  mapping(uint => int) mockedFunding;
  mapping(uint => int) mockedPNL;
  uint mockedPerpPrice;
  uint confidence;

  constructor(ISubAccounts account) MockAsset(IERC20(address(0)), account, true) {}

  function updateFundingRate() external {}

  function realizeAccountPNL(uint accountId) external {}

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

  function setMockPerpPrice(uint price, uint conf) external {
    mockedPerpPrice = price;
    confidence = conf;
  }

  function getIndexPrice() external view returns (uint, uint) {}

  function getPerpPrice() external view returns (uint, uint) {
    return (mockedPerpPrice, confidence);
  }

  function getImpactPrices() external view returns (uint, uint) {}
}
