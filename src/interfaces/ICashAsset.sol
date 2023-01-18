// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IInterestRateModel.sol";

interface ICashAsset {
  ////////////
  // Events //
  ////////////

  /// @dev Emitted when interest related state variables are updated
  event InterestAccrued(uint interestAccrued, uint borrowIndex, uint totalSupply, uint totalBorrow);

  /// @dev Emitted when the security module fee is set
  event SmFeeSet(uint fee);

  /// @dev Emitted when a new interest rate model is set
  event InterestRateModelSet(IInterestRateModel rateModel);

  /// @dev Emitted when a manager address is whitelisted or unwhitelisted
  event WhitelistManagerSet(address manager, bool whitelisted);

  /**
   * @notice Liquidation module can report loss when there is insolvency.
   *         This function will "print" the amount of cash to the target account
   *         and socilize the loss to everyone in the system
   *         this will result in turning on withdraw fee if the contract is indeed insolvent
   * @param lossAmountInCash Total amount of cash loss
   * @param accountToReceive Account to receive the new printed amount
   */
  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external;

  ////////////////
  //   Events   //
  ////////////////

  /// @dev emitted when a user deposits to an account
  event Deposit(uint accountId, address from, uint amountCashMinted, uint stableAssetDeposited);

  /// @dev emitted when a user withdraws from an account
  event Withdraw(uint accountId, address recipient, uint amountCashBurn, uint stableAssetWidrawn);

  /// @dev emitted when withdraw fee is enabled
  ///      this would imply there is an insolvency and loss is applied to all cash holders
  event WithdrawFeeEnabled(uint exchangeRate);
  
  /// @dev emitted when withdraw fee is disabled
  ///      this can only occur if the cash asset is solvent again
  event WithdrawFeeDisabled(uint exchangeRate);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error CA_NotAccount();

  /// @dev caller is not the liquidation module
  error CA_NotLiquidationModule();

  /// @dev revert when user trying to upgrade to a unknown manager
  error CA_UnknownManager();

  /// @dev caller is not owner of the account
  error CA_OnlyAccountOwner();

  /// @dev accrued interest is stale
  error CA_InterestAccrualStale(uint lastUpdatedAt, uint currentTimestamp);

  /// @dev Security module fee cut greater than 100%
  error CA_SmFeeInvalid(uint fee);
}
