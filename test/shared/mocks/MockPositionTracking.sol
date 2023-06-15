pragma solidity ^0.8.13;

import {IPositionTracking} from "../../../src/interfaces/IPositionTracking.sol";
import {IManager} from "../../../src/interfaces/IManager.sol";

contract MockPositionTracking is IPositionTracking {
  mapping(IManager => uint) public mockedTotalPosition;

  mapping(IManager => uint) public mockedTotalPositionCap;

  mapping(IManager => mapping(uint => OISnapshot)) public totalPositionBeforeTrade;

  function setTotalPositionBeforeTrade(IManager _manager, uint _tradeId, uint _oi) external {
    totalPositionBeforeTrade[_manager][_tradeId] = OISnapshot(true, uint240(_oi));
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
