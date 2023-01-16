// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ICashAsset {
  ///////////////////
  //   Functions   //
  //////////////////

  /**
   * @dev Deposit USDC and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param amount amount of USDC to deposit
   */
  function deposit(uint recipientAccount, uint amount) external;

  /**
   * @notice Withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param amount amount of stable asset in its native decimals
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint amount, address recipient) external;

  /**
   * @notice Returns latest balance without updating accounts but will update indexes
   * @param accountId The accountId to check
   */
  function calculateBalanceWithInterest(uint accountId) external returns (int balance);

  /**
   * @dev Returns the exchange rate from cash asset to stable asset
   *      this should always be equal to 1, unless we have an insolvency
   */
  function getCashToStableExchangeRate() external view returns (uint);

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error CA_NotAccount();

  /// @dev revert when user trying to upgrade to a unknown manager
  error CA_UnknownManager();

  /// @dev caller is not owner of the account
  error CA_OnlyAccountOwner();

  /// @dev accrued interest is stale
  error CA_InterestAccrualStale(uint lastUpdatedAt, uint currentTimestamp);
}
