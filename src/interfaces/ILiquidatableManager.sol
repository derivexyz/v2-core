// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IBaseManager} from "./IBaseManager.sol";
import {IPerpAsset} from "./IPerpAsset.sol";
import {IOptionAsset} from "./IOptionAsset.sol";

interface ILiquidatableManager is IBaseManager {
  /**
   * @notice can be called by anyone to settle all perp asset in an account
   */
  function settlePerpsWithIndex(uint accountId) external;

  /**
   * @notice can be called by anyone to settle option assets in an account
   */
  function settleOptions(IOptionAsset _option, uint accountId) external;

  /**
   * @dev get initial margin or maintenance margin
   */
  function getMargin(uint accountId, bool isInitial) external view returns (int);

  function getMarginAndMarkToMarket(uint accountId, bool isInitial, uint scenarioId) external view returns (int, int);
}
