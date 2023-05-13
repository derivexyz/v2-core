// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IBaseManager {
  /////////////
  // Structs //
  /////////////

  function feeCharged(uint tradeId, uint account) external view returns (uint);
}
