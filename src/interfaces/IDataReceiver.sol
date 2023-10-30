// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title IDataReceiver
 * @author Lyra
 * @notice Interface for oracles that takes data off-chain with signer data
 */
interface IDataReceiver {
  function acceptData(bytes calldata data) external;
}
