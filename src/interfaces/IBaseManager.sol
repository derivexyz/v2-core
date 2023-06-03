// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./IManager.sol";
import "./IAllowList.sol";

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

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount) external;

  function payLiquidationFee(uint accountId, uint recipient, uint cashAmount) external;

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when OI fee rate is set
  event OIFeeRateSet(address asset, uint oiFeeRate);

  event MinOIFeeSet(uint minOIFee);
  event PerpSettled(uint indexed accountId, int netCash);
  event FeeBypassedCallerSet(address caller, bool bypassed);
  event AllowListSet(IAllowList _allowList);
  event FeeRecipientSet(uint _newAcc);
  event OptionSettlementBufferUpdated(uint optionSettlementBuffer);

  ////////////
  // Errors //
  ////////////

  error BM_OIFeeRateTooHigh();

  error BM_MinOIFeeTooHigh();

  error BM_InvalidSettlementBuffer();

  /// @dev bad action
  error BN_InvalidAction();
  /// @dev User is not allowlisted, so trade is blocked
  error BM_CannotTrade();

  error BM_OnlyBlockedAccounts();

  error BM_InvalidForceWithdrawAccountState();

  error BM_InvalidForceLiquidateAccountState();

  error BM_InvalidBidPortion();

  error BM_LiquidatorCanOnlyHaveCash();

  error BM_OnlyLiquidationModule();

  error BM_OnlyAccounts();

  error BM_AssetCapExceeded();

  error BM_OnlySubAccountOwner();

  error BM_MergeOwnerMismatch();
}
