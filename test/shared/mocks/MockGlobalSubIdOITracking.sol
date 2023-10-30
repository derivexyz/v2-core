pragma solidity ^0.8.20;

import {IGlobalSubIdOITracking} from "../../../src/interfaces/IGlobalSubIdOITracking.sol";

contract MockGlobalSubIdOITracking is IGlobalSubIdOITracking {
  mapping(uint subId => uint) public openInterest;

  ///@dev SubId => tradeId => open interest snapshot
  mapping(uint => mapping(uint => SubIdOISnapshot)) public openInterestBeforeTrade;

  function setMockedOISnapshotBeforeTrade(uint _subId, uint _tradeId, uint _oi) external {
    openInterestBeforeTrade[_subId][_tradeId] = SubIdOISnapshot(true, uint240(_oi));
  }

  function setMockedOI(uint _subId, uint _oi) external {
    openInterest[_subId] = _oi;
  }
}
