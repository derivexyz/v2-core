// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IBaseManager} from "src/interfaces/IBaseManager.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";

// todo: rename to LyraManager?
interface ILiquidatableManager is IBaseManager {
  /**
   * @notice can be called by anyone to settle a perp asset in an account
   */
  function settlePerpsWithIndex(IPerpAsset _perp, uint accountId) external;

  /**
   * @dev get initial margin or maintenance margin
   */
  function getMargin(uint accountId, bool isInitial) external view returns (int);

  function getSolventAuctionUpperBound(uint accountId) external view returns (int);

  function getInsolventAuctionLowerBound(uint accountId) external view returns (int);
}
