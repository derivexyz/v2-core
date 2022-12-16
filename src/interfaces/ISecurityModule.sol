// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title Security module
/// @author Lyra
/// @notice the backstop against insolvent positions as well as staking mechanism
/// @dev If this contract is depleted then socailised losses will be enacted
interface ISecurityModule {
  // Depsoiting fees into this module
  function deposit(uint amount) external returns (bool);
  // withdrawing fees from this module
  function withdraw(uint amount) external returns (bool);
  // getting the balance of this module
  function getBalance() external view returns (uint);
}