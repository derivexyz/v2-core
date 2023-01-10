// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccounts.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";

import "synthetix/DecimalMath.sol";

contract MockManager is IManager {
  IAccounts account;

  bool revertHandleManager;
  bool revertHandleAdjustment;

  bool logAdjustmentTriggers;

  mapping(uint => uint) public accTriggeredDeltaLength;

  // acc => asset => subId => time
  mapping(uint => mapping(address => mapping(uint96 => uint))) public accAssetTriggered;

  mapping(uint => mapping(address => mapping(uint96 => int))) public accAssetAdjustmentDelta;

  constructor(address account_) {
    account = IAccounts(account_);
  }

  function handleAdjustment(uint acc, address, AccountStructs.AssetDelta[] memory deltas, bytes memory) public virtual {
    // testing mode: record all incoming "deltas"
    if (logAdjustmentTriggers) {
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
  function test() public {}

  function getSpot() external view returns (uint) {
    return 1000 * DecimalMath.UNIT; // hardcoded value not relevant to test
  }
}
