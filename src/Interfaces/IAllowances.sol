// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

// For full documentation refer to src/Allowances.sol";
interface IAllowances {

  ///////////
  // Views //
  ///////////

  function positiveSubIdAllowance(
    uint accountId, address owner, IAsset asset, uint subId, address spender
  ) external view returns (uint);

  function negativeSubIdAllowance(
    uint accountId, address owner, IAsset asset, uint subId, address spender
  ) external view returns (uint);

  function positiveAssetAllowance(
    uint accountId, address owner, IAsset asset, address spender
  ) external view returns (uint);

  function negativeAssetAllowance(
    uint accountId, address owner, IAsset asset, address spender
  ) external view returns (uint);

  ////////////
  // Errors //
  ////////////

  error NotEnoughSubIdOrAssetAllowances(
    address thower,
    address caller,
    uint accountId,
    int amount,
    uint subIdAllowance,
    uint assetAllowance
  );
}
