// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";

import {ISubAccounts} from "../../../src/interfaces/ISubAccounts.sol";
import {IManagerWhitelist} from "../../../src/interfaces/IManagerWhitelist.sol";

/**
 * @title ManagerWhitelist
 * @dev   Contract for assets to control whitelisted managers.
 * @author Lyra
 */
abstract contract ManagerWhitelist is IManagerWhitelist, Ownable2Step {
  /// @dev Account contract address
  ISubAccounts public immutable subAccounts;

  /// @dev Whitelisted managers. Only accounts controlled by whitelisted managers can trade this asset.
  mapping(address => bool) public whitelistedManager;

  /////////////////////
  //   Constructor   //
  /////////////////////

  constructor(ISubAccounts _subAccounts) {
    subAccounts = _subAccounts;
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

  function _checkCallerIsAccounts() internal view {
    if (msg.sender != address(subAccounts)) revert MW_OnlyAccounts();
  }

  ///////////////////
  //   Modifiers   //
  ///////////////////

  modifier onlyAccounts() {
    _checkCallerIsAccounts();
    _;
  }
}
