// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IDataReceiver} from "../interfaces/IDataReceiver.sol";

import {ILiquidatableManager} from "../interfaces/ILiquidatableManager.sol";
import {IPerpAsset} from "../interfaces/IPerpAsset.sol";

/**
 * @title PerpSettlementHelper
 * @notice Helper contract compliant with IDataReceiver interface, so we can settle perps if necessary before running margin checks
 */
contract PerpSettlementHelper is IDataReceiver {
  ///@dev Another public function so forge coverage won't confuse this with OptionSettlementHelper
  string public name = "PerpSettlementHelper";

  function acceptData(bytes calldata data) external {
    (address manager, address perp, uint accountId) = abi.decode(data, (address, address, uint));

    ILiquidatableManager(manager).settlePerpsWithIndex(IPerpAsset(perp), accountId);
  }
}
