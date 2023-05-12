// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

/**
 * @title IUpdatableOracle
 * @author Lyra
 * @notice Interface for oracles that takes data off-chain with signer data
 */
interface IUpdatableOracle {
  function updatePrice(bytes calldata data) external;
}
