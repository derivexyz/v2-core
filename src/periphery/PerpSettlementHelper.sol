// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IDataReceiver} from "../interfaces/IDataReceiver.sol";

import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";

/**
 * @title PerpSettlementHelper
 * @notice Helper contract compliant with IDataReceiver interface, so we can settle perps if necessary before running margin checks
 */
contract PerpSettlementHelper is IDataReceiver {
  string public constant name = "PerpSettlementHelper";

  function acceptData(bytes calldata data) external {
    (address manager, uint accountId) = abi.decode(data, (address, uint));

    ILiquidatableManager(manager).settlePerpsWithIndex(accountId);
  }
}
