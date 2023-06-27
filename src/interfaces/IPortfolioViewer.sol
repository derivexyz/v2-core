// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IStandardManager} from "./IStandardManager.sol";
import {ISubAccounts} from "../interfaces/ISubAccounts.sol";
import {IPMRM} from "../interfaces/IPMRM.sol";

/**
 * @title IPortfolioViewer
 * @author Lyra
 */
interface IPortfolioViewer {
  /**
   * @notice Arrange balances into standard manager portfolio struct
   * @param assets Array of balances for given asset and subId.
   */
  function arrangeSRMPortfolio(ISubAccounts.AssetBalance[] memory assets)
    external
    view
    returns (IStandardManager.StandardManagerPortfolio memory);

  /**
   * @dev get the original balances state before a trade is executed
   */
  function undoAssetDeltas(uint accountId, ISubAccounts.AssetDelta[] memory assetDeltas)
    external
    view
    returns (ISubAccounts.AssetBalance[] memory newAssetBalances);
}
