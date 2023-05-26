// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IManager} from "./IManager.sol";
import {IAsset} from "./IAsset.sol";

interface IWrappedERC20Asset is IAsset {
  function managerOI(IManager manager) external view returns (uint);

  function managerOICap(IManager manager) external view returns (uint);

  event OICapSet(address manager, uint oiCap);

  error WERC_ManagerChangeExceedOICap();

  error WERC_OnlyAccountOwner();

  error WERC_CannotBeNegative();
}
