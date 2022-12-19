// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/AccountStructs.sol";

/**
 * @title PermitAllowanceLib
 * @author Lyra
 * @notice hash function for PermitAllowance object
 */
library PermitAllowanceLib {

    // todo: update
    bytes32 public constant _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH = keccak256(
        "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
    );

    bytes32 public constant _ASSET_ALLOWANCE_TYPEHASH = keccak256("AssetAllowance(address,uint256,uint256)");

    bytes32 public constant _SUBID_ALLOWANCE_TYPEHASH = keccak256("SubIdAllowance(address,uint256,uint256,uint256)");

    function hash(AccountStructs.PermitAllowance memory permit) internal pure returns (bytes32) {
        uint256 assetPermits = permit.assetAllowances.length;
        uint256 subIdPermits = permit.subIdAllowances.length;

        bytes32[] memory assetAllowancesHashes = new bytes32[](assetPermits);
        for (uint256 i = 0; i < assetPermits; ++i) {
            assetAllowancesHashes[i] = _hashAssetAllowance(permit.assetAllowances[i]);
        }

        bytes32[] memory subIdAllowancesHashes = new bytes32[](subIdPermits);
        for (uint256 i = 0; i < subIdPermits; ++i) {
            subIdAllowancesHashes[i] = _hashSubIdAllowance(permit.subIdAllowances[i]);
        }

        return keccak256(
            abi.encode(
                _PERMIT_BATCH_TRANSFER_FROM_TYPEHASH,
                permit.delegate,
                permit.nonce,
                permit.accountId,
                permit.deadline,
                keccak256(abi.encodePacked(assetAllowancesHashes)),
                keccak256(abi.encodePacked(subIdAllowancesHashes))
            )
        );
    }

    function _hashAssetAllowance(AccountStructs.AssetAllowance memory allowance) private pure returns (bytes32) {
        return keccak256(abi.encode(_ASSET_ALLOWANCE_TYPEHASH, allowance));
    }

    function _hashSubIdAllowance(AccountStructs.SubIdAllowance memory allowance) private pure returns (bytes32) {
        return keccak256(abi.encode(_SUBID_ALLOWANCE_TYPEHASH, allowance));
    }

}
