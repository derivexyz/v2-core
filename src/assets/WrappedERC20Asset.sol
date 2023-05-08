// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";
import "lyra-utils/ownership/Owned.sol";

import "src/interfaces/IAccounts.sol";
import "src/interfaces/IMarginAsset.sol";
import "../interfaces/ISpotFeed.sol";

/**
 * @title Cash asset with built-in lending feature.
 * @dev   Users can deposit USDC and credit this cash asset into their accounts.
 *        Users can borrow cash by having a negative balance in their account (if allowed by manager).
 * @author Lyra
 */

contract WrappedERC20Asset is IMarginAsset, Owned {
  using SafeERC20 for IERC20Metadata;
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using SafeCast for uint128;
  using SafeCast for int;
  using SafeCast for int128;

  ISpotFeed public spotFeed;
  IAccounts public immutable accounts;
  ///@dev The token address for the wrapped asset
  IERC20Metadata public immutable wrappedAsset;
  uint8 assetDecimals;

  constructor(
    IAccounts _accounts,
    IERC20Metadata _wrappedAsset,
    ISpotFeed _spotFeed
  ) Owned() {
    accounts = _accounts;
    wrappedAsset = _wrappedAsset;
    spotFeed = _spotFeed;
    assetDecimals = _wrappedAsset.decimals();
  }

  ////////////////////////////
  //     Admin Functions    //
  ////////////////////////////


  ////////////////////////////
  //   External Functions   //
  ////////////////////////////

  /**
   * @dev Deposit USDC and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param assetAmount amount of the wrapped asset to deposit
   */
  function deposit(uint recipientAccount, uint assetAmount) external {
    wrappedAsset.safeTransferFrom(msg.sender, address(this), assetAmount);
    uint amountInAccount = assetAmount.to18Decimals(assetDecimals);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amountInAccount),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    // emit Deposit(accountId, msg.sender, cashAmount, stableAmount);
  }

  /**
   * @notice Withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param assetAmount the amount of the wrapped asset to withdraw in its native decimals
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint assetAmount, address recipient) external {
    if (msg.sender != accounts.ownerOf(accountId)) revert("Only account owner");

    // if amount pass in is in higher decimals than 18, round up the trailing amount
    // to make sure users cannot withdraw dust amount, while keeping cashAmount == 0.
    uint adjustmentAmount = assetAmount.to18DecimalsRoundUp(assetDecimals);

    wrappedAsset.safeTransfer(recipient, assetAmount);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(adjustmentAmount),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    // emit Withdraw(accountId, msg.sender, cashAmount, stableAmount);
  }

  //////////////////////////
  //   Asset value Calcs  //
  //////////////////////////

  /// @dev Returns the USD value based on oracle data - does not price in terms of stable coins
  function getValue(uint amount, uint spotShock, uint volShock) external view returns (uint value, uint confidence) {
    // TODO: get spot and shock the value

    return (amount, 1e18);
  }


  //////////////////////////
  //    Account Hooks     //
  //////////////////////////

  /**
   * @notice This function is called by the Account contract whenever a CashAsset balance is modified.
   * @dev    This function will apply any interest to the balance and return the final balance. final balance can be positive or negative.
   * @param adjustment Details about adjustment, containing account, subId, amount
   * @param preBalance Balance before adjustment
   * @param manager The manager contract that will verify the end state
   * @return finalBalance The final balance to be recorded in the account
   * @return needAllowance Return true if this adjustment should assume allowance in Account
   */
  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccounts returns (int finalBalance, bool needAllowance) {
    if (preBalance == 0 && adjustment.amount == 0) {
      return (0, false);
    }
    if (preBalance + adjustment.amount < 0) {
      revert("Cannot have a negative balance");
    }
    return (preBalance + adjustment.amount, true);
  }

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, IManager newManager) external view {}

  ///////////////////
  //   Modifiers   //
  ///////////////////

  modifier onlyAccounts() {
    if (msg.sender != address(accounts)) revert("Only accounts");
    _;
  }
}
