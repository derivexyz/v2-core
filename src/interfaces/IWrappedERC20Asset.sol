// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "./IManager.sol";
import {IAsset} from "./IAsset.sol";
import "./IPositionTracking.sol";

interface IWrappedERC20Asset is IAsset, IPositionTracking {
  function deposit(uint recipientAccount, uint assetAmount) external;
  function withdraw(uint accountId, uint assetAmount, address recipient) external;

  event Deposit(uint indexed accountId, address indexed depositor, uint amountAsset);
  event Withdraw(uint indexed accountId, address indexed recipient, uint amountAsset);

  //////////////
  //  Errors  //
  //////////////
  error WERC_OnlyAccountOwner();
  error WERC_CannotBeNegative();
}
