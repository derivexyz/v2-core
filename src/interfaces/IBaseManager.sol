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

  function feeCharged(uint tradeId, uint account) external view returns (uint);

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee) external;

  // bad action
  error BN_InvalidAction();
  /// @dev User is not allowlisted, so trade is blocked
  error BM_CannotTrade();
  error BM_OnlyBlockedAccounts();
  error BM_InvalidForceWithdrawAccountState();
  error BM_InvalidForceLiquidateAccountState();
}
