// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import "../../../../../src/risk-managers/PMRM_2_1.sol";

/// @notice Test-only helper exposing internal/admin plumbing for PMRM_2_1.
/// @dev Mirrors the pattern of PMRM_2Public, but inherits from the upgraded implementation.
contract PMRM_2_1Public is PMRM_2_1 {
  constructor() {}

  function setBalances(uint accountId, ISubAccounts.AssetBalance[] memory assets) external {
    for (uint i = 0; i < assets.length; ++i) {
      subAccounts.managerAdjustment(
        ISubAccounts.AssetAdjustment({
          acc: accountId,
          asset: assets[i].asset,
          subId: assets[i].subId,
          amount: assets[i].balance,
          assetData: bytes32(0)
        })
      );
    }
  }
}

