// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IBaseManager} from "src/interfaces/IBaseManager.sol";

interface ILiquidatableManager is IBaseManager {
  /**
   * @dev get initial margin or maintenance margin
   */
  function getMargin(uint accountId, bool isInitial) external view returns (int);
}
