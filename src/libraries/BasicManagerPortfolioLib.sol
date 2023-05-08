// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAsset} from "src/interfaces/IAsset.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IBasicManager} from "src/interfaces/IBasicManager.sol";

/**
 * @title BasicManagerPortfolioLib
 * @notice util functions for BasicManagerPortfolio structs
 */
library BasicManagerPortfolioLib {

  function addPerpToPortfolio(
    IBasicManager.BasicManagerPortfolio memory portfolio, 
    uint underlyingId,
    int balance
  ) 
    internal pure 
  {
    // find the asset that has the same id
    uint index = 0;
    portfolio.subAccounts[index].perpPosition = balance;
  }

  function addOptionToPortfolio(
    IBasicManager.BasicManagerPortfolio memory portfolio, 
    uint underlyingId,
    uint96 subId,
    int balance
  ) 
    internal pure 
  {
    // find the asset that has the same id
    uint index = 0;
    portfolio.subAccounts[index].numExpiries = 1;
    // portfolio.subAccounts[index].expiryHoldings.expiry;
    
    // find the expiryHoldings that has same expiry



  }
}
