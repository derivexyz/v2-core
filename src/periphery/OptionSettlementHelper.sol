// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IDataReceiver} from "src/interfaces/IDataReceiver.sol";

import {ILiquidatableManager} from "src/interfaces/ILiquidatableManager.sol";
import {IOption} from "src/interfaces/IOption.sol";

contract OptionSettlementHelper is IDataReceiver {
  function acceptData(bytes calldata data) external {
    (address manager, address option, uint accountId) = abi.decode(data, (address, address, uint));

    ILiquidatableManager(manager).settleOptions(IOption(option), accountId);
  }
}
