// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "../interfaces/IAsset.sol";

/**
 * @title cash asset with built-in lending feature
 * @dev
 * @author Lyra
 */
contract Lending is IAsset {

  address public immutable account;

  ///@dev whitelisted managers
  mapping (address => bool) public whitelistedManager;

  ////////////////
  //   Errors   //
  ////////////////

  /// @dev emited when user trying to upgrade to a unknown manager
  error LA_UnknownManager();

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
   * @dev    the function will imply interest rate and modify the final balance.
   * @param manager the manager contract that will verify the end state. Should verify if this is a trusted manager
   * @param caller the msg.sender that initiate the transfer, can assume to be a address authorized by user
   * @return finalBalance the final balance to be recorded in the account
   * @return needAllowance if this adjustment should require allowance from non-ERC721 approved initiator
   */
  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    int preBalance,
    IManager manager,
    address caller
  ) external returns (int finalBalance, bool needAllowance) {

    // finalBalance can go positive or negative
    finalBalance = preBalance + adjustment.amount;
    
    // need allowance if trying to deduct balance
    needAllowance = adjustment.amount < 0;
  }

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint /*accountId*/, IManager newManager) external {
    if (!whitelistedManager[newManager]) revert LA_UnknownManager();
  }
}
