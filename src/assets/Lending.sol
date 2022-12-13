// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "../interfaces/IAsset.sol";
import "../interfaces/IAccount.sol";
import "../libraries/DecimalMath.sol";
import "forge-std/Script.sol";

/**
 * @title cash asset with built-in lending feature.
 * @dev   user can deposit USDC and credit this cash asset into their account
 *        users can borrow cash by having a negative balance in their account (if allowed by manager)
 * @author Lyra
 */
contract Lending is Owned, IAsset {
  using SafeERC20 for IERC20;
  using DecimalMath for uint;
  using SafeCast for uint;
  using SafeCast for int;

  ///@dev account contract address
  IAccount public immutable account;

  ///@dev usdc address
  address public immutable usdc;

  ///@dev store usdc decimals as immutable
  uint8 private immutable usdcDecimals;

  /////////////////////////
  //   State Variables   //
  /////////////////////////

  ///@dev amount of USDC that has been supplied
  uint public totalSupply;

  ///@dev total amount of negative balances
  uint public totalBorrow;

  ///@dev total accrued fees
  uint public accruedFees;

  ///@dev borrow index
  uint public borrowIndex;

  ///@dev supply index
  uint public supplyIndex;

  ///@dev last timestamp that the interest is accrued
  uint public lastTimestamp;

  ///@dev whitelisted managers
  mapping(address => bool) public whitelistedManager;

  ///////////////////
  //   Modifiers   //
  ///////////////////
  modifier onlyAccount() {
    if (msg.sender != address(account)) revert LA_NotAccount();
    _;
  }

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(address _account, address _usdc) {
    usdc = _usdc;
    usdcDecimals = IERC20Metadata(_usdc).decimals();
    account = IAccount(_account);
  }

  //////////////////////////
  //    Account Hooks     //
  //////////////////////////

  /**
   * @notice triggered when an adjustment is triggered on the asset balance
   * @dev    we imply interest rate and modify the final balance. final balance can be positive or negative.
   * @param adjustment details about adjustment, containing account, subId, amount
   * @param preBalance balance before adjustment
   * @param manager the manager contract that will verify the end state
   * @return finalBalance the final balance to be recorded in the account
   * @return needAllowance if this adjustment should require allowance from non-ERC721 approved initiator
   */
  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    console.log("lending handle adjustment");
    _checkManager(address(manager));
    if (preBalance == 0 && adjustment.amount == 0) {
      return (0, false);
    }

    // finalBalance can go positive or negative
    finalBalance = preBalance + adjustment.amount;

    // update totalSupply and totalBorrow amounts
    // if (adjustment.amount < 0) {
    //   if ((-adjustment.amount).toUint256() > totalSupply) revert LA_WithdrawMoreThanSupply(adjustment.amount, totalSupply);
    // }

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

    // accrue interest rate
    _accrueInterest();

    // todo: accrue interest on prebalance
  
   
    // need allowance if trying to deduct balance
    needAllowance = adjustment.amount < 0;

    console.log("END of handle adjustment");
  }

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    _checkManager(address(newManager));
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
    // if (amount == 0) return;

    IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
    // console.log("here");
    uint amountInAccount = amount.convertDecimals(usdcDecimals, 18);
    // console.log("after");

    console.log("amount", amountInAccount);
    account.assetAdjustment(
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
    console.log("after again");
 
    // invoke handleAdjustment hook so the manager is checked, and interest is applied.
  }

  /**
   * @notice withdraw USDC from a Lyra account
   * @param accountId account id to withdraw
   * @param amount amount of usdc
   * @param recipient USDC recipient
   */
  function withdraw(uint accountId, uint amount, address recipient) external {
    if (msg.sender != account.ownerOf(accountId)) revert LA_OnlyAccountOwner();

    int preBalance = account.getBalance(accountId, IAsset(address(this)), 0);

    IERC20(usdc).safeTransfer(recipient, amount);

    uint cashAmount = amount.convertDecimals(usdcDecimals, 18);

    int postBalance = account.assetAdjustment(
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
   * @dev get current account cash balance
   */
  // function _getStaleBalance(uint accountId) internal view returns (int balance) {
  //   balance = account.getBalance(accountId, IAsset(address(this)), 0);
  // }

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error LA_NotAccount();

  /// @dev revert when user trying to upgrade to a unknown manager
  error LA_UnknownManager();

  /// @dev caller is not owner of the account
  error LA_OnlyAccountOwner();

  /// @dev withdraw more than supply
  error LA_WithdrawMoreThanSupply(int withdrawAmount, uint totalSupply);
  
  /// @dev accrued interest is stale
  error LA_InterestAccrualStale(uint lastUpdatedAt, uint currentTimestamp);
}
