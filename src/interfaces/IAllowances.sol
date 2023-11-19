// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IAsset} from "./IAsset.sol";

// For full documentation refer to src/Allowances.sol";
interface IAllowances {
  ////////////////
  // Allowances //
  ////////////////

  struct AssetAllowance {
    IAsset asset;
    uint positive;
    uint negative;
  }

  struct SubIdAllowance {
    IAsset asset;
    uint subId;
    uint positive;
    uint negative;
  }

  struct PermitAllowance {
    // who to approve
    address delegate;
    // nonce for each signer
    uint nonce;
    // access are granted on account bases. A signer can have multiple accounts and the signature cannot be
    // applied to permit another account
    uint accountId;
    // deadline on the permit signature
    uint deadline;
    // array of "asset allowance" to set
    IAllowances.AssetAllowance[] assetAllowances;
    // array of "subid allowance" to set
    SubIdAllowance[] subIdAllowances;
  }

  ///////////
  // Views //
  ///////////

  function positiveSubIdAllowance(uint accountId, address owner, IAsset asset, uint subId, address spender)
    external
    view
    returns (uint);

  function negativeSubIdAllowance(uint accountId, address owner, IAsset asset, uint subId, address spender)
    external
    view
    returns (uint);

  function positiveAssetAllowance(uint accountId, address owner, IAsset asset, address spender)
    external
    view
    returns (uint);

  function negativeAssetAllowance(uint accountId, address owner, IAsset asset, address spender)
    external
    view
    returns (uint);

  ////////////
  // Errors //
  ////////////

  error NotEnoughSubIdOrAssetAllowances(
    address caller, uint accountId, int amount, uint subIdAllowance, uint assetAllowance
  );
}
