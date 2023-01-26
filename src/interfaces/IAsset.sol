// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IManager.sol";

interface IAsset {
  /**
   * @notice triggered when an adjustment is triggered on the asset balance
   * @param adjustment details about adjustment, containing account, subId, amount
   * @param preBalance balance before adjustment
   * @param manager the manager contract that will verify the end state. Should verify if this is a trusted manager
   * @param caller the msg.sender that initiate the transfer. might not be the owner
   * @return finalBalance the final balance to be recorded in the account
   * @return needAllowance if this adjustment should require allowance from non-ERC721 approved initiator
   */
  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBalance,
    IManager manager,
    address caller
  ) external returns (int finalBalance, bool needAllowance);

  /**
   * @notice triggered when a user wants to migrate an account to a new manager
   * @dev an asset can block a migration to a un-trusted manager, e.g. a manager that does not take care of liquidation
   */
  function handleManagerChange(uint accountId, IManager newManager) external;
}
