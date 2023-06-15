// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IBaseManager} from "./IBaseManager.sol";
import {IPerpAsset} from "./IPerpAsset.sol";
import {IOption} from "./IOption.sol";

interface ILiquidatableManager is IBaseManager {
  /**
   * @notice can be called by anyone to settle a perp asset in an account
   */
  function settlePerpsWithIndex(IPerpAsset _perp, uint accountId) external;

  /**
   * @notice can be called by anyone to settle option assets in an account
   */
  function settleOptions(IOption _option, uint accountId) external;

  /**
   * @dev get initial margin or maintenance margin
   */
  function getMargin(uint accountId, bool isInitial) external view returns (int);

  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId) external view returns (int, int);
}
