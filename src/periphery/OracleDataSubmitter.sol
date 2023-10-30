// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../interfaces/IBaseManager.sol";
import "../interfaces/IDataReceiver.sol";

contract OracleDataSubmitter {
  function submitData(bytes calldata managerData) external {
    // parse array of data and update each oracle or take action
    IBaseManager.ManagerData[] memory managerDatas = abi.decode(managerData, (IBaseManager.ManagerData[]));
    for (uint i; i < managerDatas.length; i++) {
      IDataReceiver(managerDatas[i].receiver).acceptData(managerDatas[i].data);
    }
  }
}
