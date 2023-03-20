// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lyra-utils/ownership/Owned.sol";

import "../interfaces/IAccounts.sol";
import "../interfaces/IManagerWhitelist.sol";

/**
 * @title ManagerWhitelist
 * @dev   Abstract contract for assets to control whitelisted managers.
 * @author Lyra
 */

contract ManagerWhitelist is IManagerWhitelist, Owned {
  ///@dev Account contract address
  IAccounts public immutable accounts;

  ///@dev Whitelisted managers. Only accounts controlled by whitelisted managers can trade this asset.
  mapping(address => bool) public whitelistedManager;

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(IAccounts _accounts) {
    accounts = _accounts;
  }

  //////////////////////////////
  //   Owner-only Functions   //
  //////////////////////////////

  /**
   * @notice Whitelist or un-whitelist a manager
   * @param _manager manager address
   * @param _whitelisted true to whitelist
   */
  function setWhitelistManager(address _manager, bool _whitelisted) external onlyOwner {
    whitelistedManager[_manager] = _whitelisted;

    emit WhitelistManagerSet(_manager, _whitelisted);
  }

  ////////////////////////////
  //   Internal Functions   //
  ////////////////////////////

  /**
   * @dev Revert if manager address is not whitelisted by this contract
   * @param manager manager address
   */
  function _checkManager(address manager) internal view {
    if (!whitelistedManager[manager]) revert MW_UnknownManager();
  }

  ///////////////////
  //   Modifiers   //
  ///////////////////

  modifier onlyAccount() {
    if (msg.sender != address(accounts)) revert MW_NotAccount();
    _;
  }
}
