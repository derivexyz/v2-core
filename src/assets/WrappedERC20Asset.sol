// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "src/interfaces/IAccounts.sol";
import "src/assets/ManagerWhitelist.sol";

/**
 * @title Wrapped ERC20 Asset
 * @dev   Users can deposit the given ERC20, and can only have positive balances.
 *        The USD value of the asset can be computed for the given shocked scenario.
 * @author Lyra
 */
contract WrappedERC20Asset is ManagerWhitelist, IAsset {
  // TODO: IWrappedERC20Asset
  using SafeERC20 for IERC20Metadata;
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using SafeCast for uint128;
  using SafeCast for int;
  using SafeCast for int128;
  using DecimalMath for uint;

  ///@dev The token address for the wrapped asset
  IERC20Metadata public immutable wrappedAsset;
  uint8 public immutable assetDecimals;

  uint public OICap;
  uint public OI;

  constructor(IAccounts _accounts, IERC20Metadata _wrappedAsset) ManagerWhitelist(_accounts) {
    wrappedAsset = _wrappedAsset;
    assetDecimals = _wrappedAsset.decimals();
  }

  ////////////////////////////
  //     Admin Functions    //
  ////////////////////////////

  function setOICap(uint cap_) external onlyOwner {
    OICap = cap_;
  }

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
    uint adjustmentAmount = assetAmount.to18Decimals(assetDecimals);

    accounts.assetAdjustment(
      IAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(adjustmentAmount),
        assetData: bytes32(0)
      }),
      true,
      ""
    );

    OI += adjustmentAmount;
    if (OI > OICap) {
      revert("OI cap reached");
    }

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
      IAccounts.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(adjustmentAmount),
        assetData: bytes32(0)
      }),
      true,
      ""
    );

    OI -= adjustmentAmount;
    // emit Withdraw(accountId, msg.sender, cashAmount, stableAmount);
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
    IAccounts.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccounts returns (int finalBalance, bool needAllowance) {
    if (adjustment.amount == 0) {
      return (preBalance, false);
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
  function handleManagerChange(uint, IManager newManager) external view {
    _checkManager(address(newManager));
  }
}
