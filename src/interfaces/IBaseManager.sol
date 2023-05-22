// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./IManager.sol";

interface IBaseManager is IManager {
  /////////////
  // Structs //
  /////////////

  struct ManagerData {
    address receiver;
    bytes data;
  }

  struct SettleUnrealizedPNLData {
    uint accountId;
    address perp; // this needs to be verified
  }

  /**
   * @notice settle interest for an account
   */
  function settleInterest(uint accountId) external;

  function feeCharged(uint tradeId, uint account) external view returns (uint);

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint totalPortion, uint cashAmount) external;

  // bad action
  error BN_InvalidAction();
}
