// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "../interfaces/IAsset.sol";
import "../interfaces/IAccounts.sol";
import "../interfaces/ICashAsset.sol";
import "../libraries/DecimalMath.sol";

/**
 * @title Cash asset with built-in lending feature.
 * @dev   Users can deposit USDC and credit this cash asset into their accounts.
 *        Users can borrow cash by having a negative balance in their account (if allowed by manager).
 * @author Lyra
 */
contract CashAsset is ICashAsset, Owned, IAsset {
  using SafeERC20 for IERC20Metadata;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  ///@dev Account contract address
  IAccounts public immutable accounts;

  ///@dev The token address for stable coin
  IERC20Metadata public immutable stableAsset;

  ///@dev Store stable coin decimal as immutable
  uint8 private immutable stableDecimals;

  /////////////////////////
  //   State Variables   //
  /////////////////////////

  ///@dev Total amount of positive balances
  uint public totalSupply;

  ///@dev Total amount of negative balances
  uint public totalBorrow;

  ///@dev Total accrued fees from interest
  uint public accruedFees;

  ///@dev Represents the growth of $1 of debt since deploy
  uint public borrowIndex;

  ///@dev Represents the growth of $1 of positive balance since deploy
  uint public supplyIndex;

  ///@dev Last timestamp that the interest was accrued
  uint public lastTimestamp;

  ///@dev Whitelisted managers. Only accounts controlled by whitelisted managers can trade this asset.
  mapping(address => bool) public whitelistedManager;

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(IAccounts _accounts, IERC20Metadata _stableAsset) {
    stableAsset = _stableAsset;
    stableDecimals = _stableAsset.decimals();
    accounts = _accounts;
  }

  //////////////////////////////
  //   Owner-only Functions   //
  //////////////////////////////

  /**
   * @notice whitelist or un-whitelist a manager
   * @param _manager manager address
   * @param _whitelisted true to whitelist
   */
  function setWhitelistManager(address _manager, bool _whitelisted) external onlyOwner {
    whitelistedManager[_manager] = _whitelisted;
  }

  ////////////////////////////
  //   External Functions   //
  ////////////////////////////

  /**
   * @dev deposit USDC and increase account balance
   * @param recipientAccount account id to receive the cash asset
   * @param amount amount of USDC to deposit
   */
  function deposit(uint recipientAccount, uint amount) external {
    stableAsset.safeTransferFrom(msg.sender, address(this), amount);
    uint amountInAccount = amount.to18Decimals(stableDecimals);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amountInAccount),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );

    // invoke handleAdjustment hook so the manager is checked, and interest is applied.
  }

  /**
   * @notice withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param amount amount of stable asset in its native decimals
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint amount, address recipient) external {
    if (msg.sender != accounts.ownerOf(accountId)) revert LA_OnlyAccountOwner();

    stableAsset.safeTransfer(recipient, amount);

    uint cashAmount = amount.to18Decimals(stableDecimals);

    accounts.assetAdjustment(
      AccountStructs.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(cashAmount),
        assetData: bytes32(0)
      }),
      true, // do trigger callback on handleAdjustment so we apply interest
      ""
    );
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
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));
    if (preBalance == 0 && adjustment.amount == 0) {
      return (0, false);
    }

    // accrue interest rate
    _accrueInterest();

    // todo: accrue interest on prebalance

    // finalBalance can go positive or negative
    finalBalance = preBalance + adjustment.amount;

    // need allowance if trying to deduct balance
    needAllowance = adjustment.amount < 0;

    // update totalSupply and totalBorrow amounts
    _updateSupplyAndBorrow(preBalance, finalBalance);
  }

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    _checkManager(address(newManager));
  }

  ////////////////////////////
  //   Internal Functions   //
  ////////////////////////////

  /**
   * @dev revert if manager address is not whitelisted by this contract
   * @param manager manager address
   */
  function _checkManager(address manager) internal view {
    if (!whitelistedManager[manager]) revert LA_UnknownManager();
  }

  /**
   * @dev update interest rate
   */
  function _accrueInterest() internal {
    //todo: actual interest updates
    // uint util = borrowIndex / supplyIndex;

    lastTimestamp = block.timestamp;
  }

  /**
   * @dev Updates state of totalSupply and totalBorrow
   * @param preBalance The balance before the asset adjustment was made
   * @param finalBalance The balance after the asset adjustment was made
   */
  function _updateSupplyAndBorrow(int preBalance, int finalBalance) internal {
    if (preBalance <= 0 && finalBalance <= 0) {
      totalBorrow = (totalBorrow.toInt256() + (preBalance - finalBalance)).toUint256();
    } else if (preBalance >= 0 && finalBalance >= 0) {
      totalSupply = (totalSupply.toInt256() + (finalBalance - preBalance)).toUint256();
    } else if (preBalance < 0 && finalBalance > 0) {
      totalBorrow -= (-preBalance).toUint256();
      totalSupply += finalBalance.toUint256();
    } else {
      // (preBalance > 0 && finalBalance < 0)
      totalBorrow += (-finalBalance).toUint256();
      totalSupply -= preBalance.toUint256();
    }
  }

  /**
   * @dev get current account cash balance
   */
  // function _getStaleBalance(uint accountId) internal view returns (int balance) {
  //   balance = accounts.getBalance(accountId, IAsset(address(this)), 0);
  // }

  ///////////////////
  //   Modifiers   //
  ///////////////////

  modifier onlyAccount() {
    if (msg.sender != address(accounts)) revert LA_NotAccount();
    _;
  }
}
