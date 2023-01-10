// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/interfaces/IPCRM.sol";
import "../../../src/interfaces/IManager.sol";
import "../../../src/interfaces/IAsset.sol";
import "../../../src/interfaces/IAccounts.sol";

contract MockIPCRM is IPCRM, IManager {
  address account;

  mapping(uint => int) public accMargin;
  mapping(uint => bool) public accHasAssets;

  constructor(address _account) {
    account = _account;
  }

  function getSortedHoldings(uint accountId)
    external
    view
    virtual
    returns (ExpiryHolding[] memory expiryHoldings, int cash)
  {
    // TODO: filler code
  }

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
    external
    virtual
    returns (int finalInitialMargin, ExpiryHolding[] memory, int cash)
  {
    // TODO: filler code
  }

  function getSpot() external view virtual returns (uint spot) {
    // TODO: filler code
    return 1000;
  }

  function getAccountValue(uint accountId) external view virtual returns (uint) {
    // TODO: filler code
    return 0;
  }

  function getInitialMargin(uint accountId) external virtual returns (int) {
    // TODO: filler code
    return accMargin[accountId];
  }

  function getMaintenanceMargin(uint accountId) external returns (uint) {
    // TODO: filler code
    return 0;
  }

  function getGroupedHoldings(uint accountId) external view virtual returns (ExpiryHolding[] memory expiryHoldings) {
    // TODO: filler code
    if (accHasAssets[accountId]) {
      ExpiryHolding[] memory expiryHoldings = new ExpiryHolding[](1);
      StrikeHolding[] memory strikeHoldings = new StrikeHolding[](4);

      strikeHoldings[0] = StrikeHolding(1000, 1, 1, 1);
      strikeHoldings[1] = StrikeHolding(2000, 3, -1, 1);
      strikeHoldings[2] = StrikeHolding(3000, 4, -2, 1);
      strikeHoldings[3] = StrikeHolding(4000, 5, 10, 1);

      expiryHoldings[0] = ExpiryHolding(block.timestamp + 2 weeks, 4, strikeHoldings);
      return expiryHoldings;
    }

    ExpiryHolding[] memory expiryHoldings = new ExpiryHolding[](0);
    return expiryHoldings;
  }

  function getCashAmount(uint accountId) external view virtual returns (int) {
    // TODO: filer coder
    return 0;
  }

  function handleAdjustment(
    uint accountId,
    address caller,
    AccountStructs.AssetDelta[] memory deltas,
    bytes memory data
  ) external virtual {
    // TODO: filler code
  }

  /**
   * @notice triggered when a user want to change to a new manager
   * @dev    a manager should only allow migrating to another manager it trusts.
   */
  function handleManagerChange(uint accountId, IManager newManager) external {
    // TODO: filler code
  }

  function depositMargin(uint accountId, int amount) external returns (int) {
    accMargin[accountId] += amount;
    return accMargin[accountId];
  }

  function giveAssets(uint accountId) external {
    accHasAssets[accountId] = true;
  }

  function test() public {}
}
