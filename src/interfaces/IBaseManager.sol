// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./IManager.sol";

interface IBaseManager is IManager {
  /////////////
  // Structs //
  /////////////

  struct OracleData {
    address oracle;
    bytes data;
  }

  function feeCharged(uint tradeId, uint account) external view returns (uint);

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee) external;
}
