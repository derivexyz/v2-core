// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAsset} from "src/interfaces/IAsset.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IManager} from "src/interfaces/IManager.sol";

import "lyra-utils/decimals/DecimalMath.sol";

contract MockManager is IManager {
  IAccounts account;

  bool revertHandleManager;
  bool revertHandleAdjustment;

  bool logAdjustmentTriggers;

  uint public recordedTradeId;

  mapping(uint => uint) public accTriggeredDeltaLength;

  uint mockedSpot;

  // acc => asset => subId => time
  mapping(uint => mapping(address => mapping(uint96 => uint))) public accAssetTriggered;

  mapping(uint => mapping(address => mapping(uint96 => int))) public accAssetAdjustmentDelta;

  constructor(address account_) {
    account = IAccounts(account_);
  }

  function handleAdjustment(uint acc, uint tradeId, address, IAccounts.AssetDelta[] memory deltas, bytes memory)
    public
    virtual
  {
    // testing mode: record all incoming "deltas"
    if (logAdjustmentTriggers) {
      recordedTradeId = tradeId;
      accTriggeredDeltaLength[acc] = deltas.length;
      for (uint i; i < deltas.length; i++) {
        accAssetTriggered[acc][address(deltas[i].asset)][deltas[i].subId]++;
        accAssetAdjustmentDelta[acc][address(deltas[i].asset)][deltas[i].subId] += deltas[i].delta;
      }
    }

    if (revertHandleAdjustment) revert();
  }

  function handleManagerChange(uint, IManager) public view virtual {
    if (revertHandleManager) revert();
  }

  function receiveNewAccount(uint, uint, address, bytes calldata) public view virtual override {}

  function setRevertHandleManager(bool _revert) external {
    revertHandleManager = _revert;
  }

  function setRevertHandleAdjustment(bool _revert) external {
    revertHandleAdjustment = _revert;
  }

  function setLogAdjustmentTriggers(bool _log) external {
    logAdjustmentTriggers = _log;
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public virtual {}

  function getSpot() external view returns (uint) {
    return mockedSpot;
  }

  function setMockedSpot(uint _spot) external {
    mockedSpot = _spot;
  }
}
