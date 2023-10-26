// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "./IManager.sol";

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

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint reservedCash) external;

  function payLiquidationFee(uint accountId, uint recipient, uint cashAmount) external;

  function maxAccountSize() external view returns (uint);

  ////////////////
  //   Events   //
  ////////////////

  event MinOIFeeSet(uint minOIFee);

  event CalleeWhitelisted(address callee);

  event PerpSettled(uint indexed accountId, address perp, int pnl, int funding);

  event OptionSettled(uint indexed accountId, address option, uint subId, int amount, int value);

  event FeeBypassedCallerSet(address caller, bool bypassed);

  event FeeRecipientSet(uint _newAcc);

  event MaxAccountSizeUpdated(uint maxAccountSize);

  event TrustedRiskAssessorUpdated(address riskAssessor, bool trusted);

  ////////////
  // Errors //
  ////////////

  error BM_MinOIFeeTooHigh();

  error BM_InvalidSettlementBuffer();

  /// @dev bad action
  error BN_InvalidAction();

  error BM_InvalidBidPortion();

  error BM_AccountUnderLiquidation();

  error BM_LiquidatorCanOnlyHaveCash();

  error BM_OnlyLiquidationModule();

  error BM_OnlyAccounts();

  error BM_AssetCapExceeded();

  error BM_OnlySubAccountOwner();

  error BM_MergeOwnerMismatch();

  error BM_UnauthorizedCall();

  error BM_InvalidMaxAccountSize();

  error BM_NotImplemented();
}
