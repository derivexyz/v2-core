// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./IPositionTracking.sol";
import "./IERC20BasedAsset.sol";

interface IWrappedERC20Asset is IERC20BasedAsset, IPositionTracking {
  //////////////
  //  Errors  //
  //////////////
  error WERC_OnlyAccountOwner();
  error WERC_CannotBeNegative();
  error WERC_InvalidSubId();
}
