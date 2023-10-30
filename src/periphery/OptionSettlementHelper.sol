// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IDataReceiver} from "../interfaces/IDataReceiver.sol";

import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";
import {IOptionAsset} from "../interfaces/IOptionAsset.sol";

/**
 * @title OptionSettlementHelper
 * @notice Helper contract compliant with IDataReceiver interface, so we can settle options if necessary before running margin checks
 */
contract OptionSettlementHelper is IDataReceiver {
  string public constant name = "OptionSettlementHelper";

  function acceptData(bytes calldata data) external {
    (address manager, address option, uint accountId) = abi.decode(data, (address, address, uint));

    ILiquidatableManager(manager).settleOptions(IOptionAsset(option), accountId);
  }
}
