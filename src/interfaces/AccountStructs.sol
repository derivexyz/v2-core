// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

// For full documentation refer to src/Account.sol";
interface AccountStructs {
  /////////////////////
  // Storage Structs //
  /////////////////////

  struct BalanceAndOrder {
    // balance of (asset, subId)
    int240 balance;
    // index in heldAssets() or getAccountBalances()
    uint16 order;
  }

  struct HeldAsset {
    IAsset asset;
    uint96 subId;
  }

  struct AssetDelta {
    IAsset asset;
    uint96 subId;
    int delta;
  }

  // the struct is used to easily manage 2 dimensional array
  struct AssetDeltaArrayCache {
    uint used;
    AssetDelta[100] deltas;
  }

  /////////////////////////
  // Memory-only Structs //
  /////////////////////////

  struct AssetBalance {
    IAsset asset;
    // adjustments will revert if > uint96
    uint subId;
    // base layer only stores up to int240
    int balance;
  }

  struct AssetTransfer {
    // credited by amount
    uint fromAcc;
    // debited by amount
    uint toAcc;
    IAsset asset;
    // adjustments will revert if >uint96
    uint subId;
    // reverts if transfer amount > uint240
    int amount;
    // data passed into asset.handleAdjustment()
    bytes32 assetData;
  }

  struct AssetAdjustment {
    uint acc;
    IAsset asset;
    // reverts for subIds > uint96
    uint subId;
    // reverts if transfer amount > uint240
    int amount;
    // data passed into asset.handleAdjustment()
    bytes32 assetData;
  }

  struct PermitAllowance {
    // who to approve
    address delegate;
    // nonce for each signer
    uint nonce;
    // access are granted on account bases. A signer can have multiple accounts and it cannot be used
    // to permit another account
    uint accountId;
    // deadline on the permit signature
    uint deadline;
    AssetAllowance[] assetAllowances;
    SubIdAllowance[] subIdAllowances;
  }

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
}
