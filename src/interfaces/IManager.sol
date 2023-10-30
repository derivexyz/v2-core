// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {ISubAccounts} from "./ISubAccounts.sol";

interface IManager {
  /**
   * @notice triggered at the end of a tx when any balance of the account is updated
   * @dev a manager should properly check the final stateo of an account
   * @param tradeId unique number attached to a batched transfers.
   *                It is possible that this hook will receive multiple calls with different tradeIds within 1 transaction if there were
   *                recursive calls to Account.submitTransfer (call submitTrnasfer again in this hook).
   */
  function handleAdjustment(
    uint accountId,
    uint tradeId,
    address caller,
    ISubAccounts.AssetDelta[] memory deltas,
    bytes memory data
  ) external;
}
