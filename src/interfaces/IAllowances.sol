// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

// For full documentation refer to src/Allowances.sol";
interface IAllowances {
    ///////////
    // Views //
    ///////////

    function positiveSubIdAllowance(
        uint256 accountId,
        address owner,
        IAsset asset,
        uint256 subId,
        address spender
    )
        external
        view
        returns (uint256);

    function negativeSubIdAllowance(
        uint256 accountId,
        address owner,
        IAsset asset,
        uint256 subId,
        address spender
    )
        external
        view
        returns (uint256);

    function positiveAssetAllowance(
        uint256 accountId,
        address owner,
        IAsset asset,
        address spender
    )
        external
        view
        returns (uint256);

    function negativeAssetAllowance(
        uint256 accountId,
        address owner,
        IAsset asset,
        address spender
    )
        external
        view
        returns (uint256);

    ////////////
    // Errors //
    ////////////

    error NotEnoughSubIdOrAssetAllowances(
        address caller,
        uint256 accountId,
        int256 amount,
        uint256 subIdAllowance,
        uint256 assetAllowance
    );
}
