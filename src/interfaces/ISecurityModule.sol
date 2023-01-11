// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title ISecurityModule
 * @author Lyra
 * @notice interface for ISecurityModule. For full functionality, see src/SecurityModule
 */
interface ISecurityModule {
  //////////////
  // Function //
  //////////////

  function requestPayout(uint accountId, uint amountCashNeeded) external returns (uint amountCashDeposited);

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted when a module is added to / remove from the whitelist
   */
  event ModuleWhitelisted(address module, bool iswhitelisted);

  /**
   * @dev Emitted when there is a pay out from the security module
   */
  event SecurityModulePaidOut(uint accountId, uint cashAmount);

  ////////////
  // Errors //
  ////////////

  error SM_NotWhitelisted();
}
