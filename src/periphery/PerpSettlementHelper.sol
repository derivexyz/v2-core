// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IDataReceiver} from "src/interfaces/IDataReceiver.sol";

import {ILiquidatableManager} from "src/interfaces/ILiquidatableManager.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";

contract PerpSettlementHelper is IDataReceiver {
  function acceptData(bytes calldata data) external {
    (address manager, address perp, uint accountId) = abi.decode(data, (address, address, uint));

    ILiquidatableManager(manager).settlePerpsWithIndex(IPerpAsset(perp), accountId);
  }
}
