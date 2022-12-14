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
        int256 delta;
    }

    // the struct is used to easily manage 2 dimensional array
    struct AssetDeltaArrayCache {
        uint256 used;
        AssetDelta[100] deltas;
    }

    /////////////////////////
    // Memory-only Structs //
    /////////////////////////

    struct AssetBalance {
        IAsset asset;
        // adjustments will revert if > uint96
        uint256 subId;
        // base layer only stores up to int240
        int256 balance;
    }

    struct AssetTransfer {
    // credited by amount
        uint256 fromAcc;
        // debited by amount
        uint256 toAcc;
        IAsset asset;
        // adjustments will revert if >uint96
        uint256 subId;
        // reverts if transfer amount > uint240
        int256 amount;
        // data passed into asset.handleAdjustment()
        bytes32 assetData;
    }

    struct AssetAdjustment {
        uint256 acc;
        IAsset asset;
        // reverts for subIds > uint96
        uint256 subId;
        // reverts if transfer amount > uint240
        int256 amount;
        // data passed into asset.handleAdjustment()
        bytes32 assetData;
    }

    ////////////////
    // Allowances //
    ////////////////

    struct AssetAllowance {
        IAsset asset;
        uint256 positive;
        uint256 negative;
    }

    struct SubIdAllowance {
        IAsset asset;
        uint256 subId;
        uint256 positive;
        uint256 negative;
    }
}
