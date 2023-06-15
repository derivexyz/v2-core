// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAsset} from "./IAsset.sol";
import {IInterestRateModel} from "./IInterestRateModel.sol";
import {IManager} from "./IManager.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20BasedAsset} from "./IERC20BasedAsset.sol";

interface ICashAsset is IERC20BasedAsset {
  /**
   * @dev Deposit and create a new account
   * @param recipient user for who the new account is created
   * @param stableAmount amount of stable coins to deposit
   * @param manager manager of the new account
   */
  function depositToNewAccount(address recipient, uint stableAmount, IManager manager)
    external
    returns (uint newAccountId);

  /**
   * @notice Liquidation module can report loss when there is insolvency.
   *         This function will "print" the amount of cash to the target account
   *         and socialize the loss to everyone in the system
   *         this will result in turning on withdraw fee if the contract is indeed insolvent
   * @param lossAmountInCash Total amount of cash loss
   * @param accountToReceive Account to receive the new printed amount
   */
  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external;

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

  /**
   * @notice Allows whitelisted manager to adjust netSettledCash
   * @dev Required to track printed cash for asymmetric settlements
   * @param amountCash Amount of cash printed or burned
   */
  function updateSettledCash(int amountCash) external;

  /**
   * @notice Allows the account's risk manager to forcefully send all cash to the account owner
   */
  function forceWithdraw(uint accountId) external;

  ////////////////
  //   Events   //
  ////////////////

  /// @dev Emitted when interest related state variables are updated
  event InterestAccrued(uint interestAccrued, uint borrowIndex, uint totalSupply, uint totalBorrow);

  /// @dev Emitted when the security module fee is set
  event SmFeeSet(uint fee);

  /// @dev Emitted when the recipient is set
  event SmFeeRecipientSet(uint recipientAcc);

  /// @dev Emitted when a new liquidation module is set
  event LiquidationModuleSet(address liquidationModule);

  /// @dev Emitted when a new interest rate model is set
  event InterestRateModelSet(IInterestRateModel rateModel);

  /// @dev emitted when a user deposits to an account
  event Deposit(uint accountId, address from, uint amountCashMinted, uint wrappedAssetDeposited);

  /// @dev emitted when a user withdraws from an account
  event Withdraw(uint accountId, address recipient, uint amountCashBurn, uint wrappedAssetWidrawn);

  /// @dev Emitted when asymmetric print/burn occurs for settlement
  event SettledCashUpdated(int amountChanged, int currentSettledCash);

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

  /// @dev SubId passed into adjustment is not 0
  error CA_InvalidSubId();

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

  /// @dev The caller of force withdraw was not the account's risk manager
  error CA_ForceWithdrawNotAuthorized();

  /// @dev Calling force withdraw when user has a negative balance
  error CA_ForceWithdrawNegativeBalance();
}
