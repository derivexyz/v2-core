// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

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

  /**
   * @dev return the account id of security module
   */
  function accountId() external returns (uint);

  ////////////
  // Events //
  ////////////

  /**
   * @dev Emitted when a module is added to / remove from the whitelist
   */
  event ModuleWhitelisted(address module, bool isWhitelisted);

  /**
   * @dev Emitted when there is a pay out from the security module
   */
  event SecurityModulePaidOut(uint accountId, uint cashAmountNeeded, uint cashAmountPaid);

  ////////////
  // Errors //
  ////////////

  error SM_NotWhitelisted();
  error SM_BalanceBelowPCRMStaticCashOffset(uint cashBalance, uint staticCashOffset);
}
