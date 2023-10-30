// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../..//shared/mocks/MockManager.sol";

import {ILiquidatableManager} from "../../../src/interfaces/ILiquidatableManager.sol";
import {IDutchAuction} from "../../../src/interfaces/IDutchAuction.sol";
import {IPerpAsset} from "../../../src/interfaces/IPerpAsset.sol";
import {IOptionAsset} from "../../../src/interfaces/IOptionAsset.sol";

contract MockLiquidatableManager is MockManager, ILiquidatableManager {
  mapping(uint tradeId => mapping(uint account => uint fee)) public mockFeeCharged;
  mapping(uint account => mapping(bool isInitial => mapping(uint scenario => int margin))) public mockMargin;

  mapping(uint => int) public mockMarkToMarket;

  mapping(uint => bool) public perpSettled;

  uint public feePaid;

  uint public maxAccountSize = 200;

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

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint reservedCash) external {
    // do nothing
  }

  function payLiquidationFee(uint, uint, uint cashAmount) external {
    feePaid += cashAmount;
  }

  function getMargin(uint accountId, bool isInitial) external view override returns (int) {
    return mockMargin[accountId][isInitial][0];
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

  function settlePerpsWithIndex(uint accountId) external {
    perpSettled[accountId] = true;
  }

  function settleOptions(IOptionAsset _option, uint accountId) external {}

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public override {}
}
