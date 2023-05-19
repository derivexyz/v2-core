import {IDataReceiver} from "src/interfaces/IDataReceiver.sol";

import {ILiquidatableManager} from "src/interfaces/ILiquidatableManager.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";

contract SettlementHelper is IDataReceiver {
  function acceptData(bytes calldata data) external {
    (address manager, address perp, uint accountId) = abi.decode(data, (address, address, uint));

    ILiquidatableManager(manager).settlePerpsWithIndex(IPerpAsset(perp), accountId);
  }
}
