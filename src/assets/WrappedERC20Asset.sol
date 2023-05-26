// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/ConvertDecimals.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IAsset} from "src/interfaces/IAsset.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IWrappedERC20Asset} from "src/interfaces/IWrappedERC20Asset.sol";
import {ManagerWhitelist} from "src/assets/ManagerWhitelist.sol";

/**
 * @title Wrapped ERC20 Asset
 * @dev   Users can deposit the given ERC20, and can only have positive balances.
 *        The USD value of the asset can be computed for the given shocked scenario.
 * @author Lyra
 */
contract WrappedERC20Asset is ManagerWhitelist, IWrappedERC20Asset {
  // TODO: IWrappedERC20Asset
  // TODO: cleanup libs
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

  mapping(IManager => uint) public managerOI;

  mapping(IManager => uint) public managerOICap;

  constructor(IAccounts _accounts, IERC20Metadata _wrappedAsset) ManagerWhitelist(_accounts) {
    wrappedAsset = _wrappedAsset;
    assetDecimals = _wrappedAsset.decimals();
  }

  ////////////////////////////
  //      Admin - Only      //
  ////////////////////////////
  function setOICap(IManager manager, uint cap) external onlyOwner {
    managerOICap[manager] = cap;

    emit OICapSet(address(manager), cap);
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

    // emit Deposit(accountId, msg.sender, cashAmount, stableAmount);
  }

  /**
   * @notice Withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param assetAmount the amount of the wrapped asset to withdraw in its native decimals
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint assetAmount, address recipient) external {
    if (msg.sender != accounts.ownerOf(accountId)) revert WERC_OnlyAccountOwner();

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
      true, // invoke the handleAdjustment hook
      ""
    );

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
    _checkManager(address(manager));
    // only update the OI for each manager but didn't check cap. It should be checked by the manager if needed at the end of all transfer
    // otherwise a transfer might fail if += amount is processed first
    managerOI[manager] = (managerOI[manager].toInt256() + adjustment.amount).toUint256();

    if (adjustment.amount == 0) {
      return (preBalance, false);
    }
    finalBalance = preBalance + adjustment.amount;

    if (finalBalance < 0) revert WERC_CannotBeNegative();

    return (finalBalance, adjustment.amount < 0);
  }

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint accountId, IManager newManager) external onlyAccounts {
    _checkManager(address(newManager));

    uint balance = accounts.getBalance(accountId, IAsset(address(this)), 0).toUint256();
    managerOI[accounts.manager(accountId)] -= balance;
    managerOI[newManager] += balance;

    if (managerOI[newManager] > managerOICap[newManager]) revert WERC_ManagerChangeExceedOICap();
  }
}
