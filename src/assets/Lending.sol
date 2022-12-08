// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/access/Ownable.sol";
import "../interfaces/IAsset.sol";

/**
 * @title cash asset with built-in lending feature.
 * @dev   user can deposit USDC and credit this cash asset into their account
 *        users can borrow cash by having a negative balance in their account (if allowed by manager)
 * @author Lyra
 */
contract Lending is Ownable, IAsset {
  ///@dev account contract address
  address public immutable account;

  /////////////////////////
  //   State Variables   //
  /////////////////////////

  ///@dev borrow index
  uint public borrowIndex;

  ///@dev supply index
  uint public supplyIndex;

  ///@dev last timestamp that the interest is accrued
  uint public lastTimestamp;

  ///@dev whitelisted managers
  mapping(address => bool) public whitelistedManager;

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev caller is not account
  error LA_NotAccount();

  /// @dev revert when user trying to upgrade to a unknown manager
  error LA_UnknownManager();

  ///////////////////
  //   Modifiers   //
  ///////////////////
  modifier onlyAccount() {
    if (msg.sender != account) revert LA_NotAccount();
    _;
  }

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(address _account) {
    account = _account;
  }

  //////////////////////////
  //   IAsset Functions   //
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
    // todo: verify manager

    // accurue interest rate
    _accurueInterest();

    // todo: accrue interest on prebalance

    // finalBalance can go positive or negative
    finalBalance = preBalance + adjustment.amount;

    // need allowance if trying to deduct balance
    needAllowance = adjustment.amount < 0;
  }

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    if (!whitelistedManager[address(newManager)]) revert LA_UnknownManager();
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

  ////////////////////////////
  //   Internal Functions   //
  ////////////////////////////

  /**
   * @dev update interest rate
   */
  function _accurInterest() internal {
    //todo: actual interest updates

    lastTimestamp = block.timestamp;
  }
}
