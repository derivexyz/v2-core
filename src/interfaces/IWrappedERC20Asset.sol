// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IERC20BasedAsset} from "./IERC20BasedAsset.sol";
import {IPositionTracking} from "./IPositionTracking.sol";

interface IWrappedERC20Asset is IERC20BasedAsset, IPositionTracking {
  //////////////
  //  Errors  //
  //////////////
  error WERC_OnlyAccountOwner();
  error WERC_CannotBeNegative();
  error WERC_InvalidSubId();
}
