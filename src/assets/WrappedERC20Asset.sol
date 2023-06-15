// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {ConvertDecimals} from "lyra-utils/decimals/ConvertDecimals.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IAsset} from "../interfaces/IAsset.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IWrappedERC20Asset} from "../interfaces/IWrappedERC20Asset.sol";
import {ManagerWhitelist} from "./utils/ManagerWhitelist.sol";
import {PositionTracking} from "./utils/PositionTracking.sol";

/**
 * @title Wrapped ERC20 Asset
 * @dev   Users can deposit the given ERC20, and can only have positive balances.
 * @author Lyra
 */
contract WrappedERC20Asset is ManagerWhitelist, PositionTracking, IWrappedERC20Asset {
  using SafeERC20 for IERC20Metadata;
  using ConvertDecimals for uint;
  using SafeCast for uint;
  using SafeCast for int;

  /// @dev The token address for the wrapped asset
  IERC20Metadata public immutable wrappedAsset;
  uint8 public immutable assetDecimals;

  constructor(ISubAccounts _subAccounts, IERC20Metadata _wrappedAsset) ManagerWhitelist(_subAccounts) {
    wrappedAsset = _wrappedAsset;
    assetDecimals = _wrappedAsset.decimals();
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

    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(adjustmentAmount),
        assetData: bytes32(0)
      }),
      true,
      ""
    );

    emit Deposit(recipientAccount, msg.sender, assetAmount);
  }

  /**
   * @notice Withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param assetAmount the amount of the wrapped asset to withdraw in its native decimals
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint assetAmount, address recipient) external {
    if (msg.sender != subAccounts.ownerOf(accountId)) revert WERC_OnlyAccountOwner();

    // if amount pass in is in higher decimals than 18, round up the trailing amount
    // to make sure users cannot withdraw dust amount, while keeping cashAmount == 0.
    uint adjustmentAmount = assetAmount.to18DecimalsRoundUp(assetDecimals);

    wrappedAsset.safeTransfer(recipient, assetAmount);

    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(adjustmentAmount),
        assetData: bytes32(0)
      }),
      true, // invoke the handleAdjustment hook
      ""
    );

    emit Withdraw(accountId, msg.sender, assetAmount);
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
    ISubAccounts.AssetAdjustment memory adjustment,
    uint tradeId,
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccounts returns (int finalBalance, bool needAllowance) {
    if (adjustment.subId != 0) revert WERC_InvalidSubId();

    _checkManager(address(manager));

    _takeTotalOISnapshotPreTrade(manager, tradeId);
    _updateTotalOI(manager, preBalance, adjustment.amount);

    if (adjustment.amount == 0) return (preBalance, false);

    finalBalance = preBalance + adjustment.amount;

    if (finalBalance < 0) revert WERC_CannotBeNegative();

    return (finalBalance, adjustment.amount < 0);
  }

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager.
   * @dev Blocks updating to non-whitelisted manager.
   */
  function handleManagerChange(uint accountId, IManager newManager) external onlyAccounts {
    _checkManager(address(newManager));

    uint pos = subAccounts.getBalance(accountId, IAsset(address(this)), 0).toUint256();
    _migrateManagerOI(pos, subAccounts.manager(accountId), newManager);
  }
}
