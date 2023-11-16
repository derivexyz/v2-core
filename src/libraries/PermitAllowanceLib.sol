// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IAllowances} from "../interfaces/IAllowances.sol";

/**
 * @title PermitAllowanceLib
 * @author Lyra
 * @notice hash function for PermitAllowance object
 */
library PermitAllowanceLib {
  bytes32 public constant PERMIT_ALLOWANCE_TYPEHASH = keccak256(
    "PermitAllowance(address delegate,uint256 nonce,uint256 accountId,uint256 deadline,(address asset,uint256 positive,uint256 negative)[] assetAllowances,(address asset,uint256 subId,uint256 positive,uint256 negative)[] subIdAllowances)"
  );

  bytes32 public constant ASSET_ALLOWANCE_TYPEHASH =
    keccak256("AssetAllowance(address asset,uint256 positive,uint256 negative)");

  bytes32 public constant SUBID_ALLOWANCE_TYPEHASH =
    keccak256("SubIdAllowance(address asset,uint256 subId,uint256 positive,uint256 negative)");

  /**
   * @dev hash the permit struct
   *      this function only hash the permit struct, needs to be combined with domain seperator to prevent replay attack
   *      and also to be compliant to EIP712 standard
   * @param permit permit struct to be hashed
   */
  function hash(IAllowances.PermitAllowance memory permit) internal pure returns (bytes32) {
    uint assetPermits = permit.assetAllowances.length;
    uint subIdPermits = permit.subIdAllowances.length;

    bytes32[] memory assetAllowancesHashes = new bytes32[](assetPermits);
    for (uint i = 0; i < assetPermits; ++i) {
      assetAllowancesHashes[i] = _hashAssetAllowance(permit.assetAllowances[i]);
    }

    bytes32[] memory subIdAllowancesHashes = new bytes32[](subIdPermits);
    for (uint i = 0; i < subIdPermits; ++i) {
      subIdAllowancesHashes[i] = _hashSubIdAllowance(permit.subIdAllowances[i]);
    }

    return keccak256(
      abi.encode(
        PERMIT_ALLOWANCE_TYPEHASH,
        permit.delegate,
        permit.nonce,
        permit.accountId,
        permit.deadline,
        keccak256(abi.encode(assetAllowancesHashes)),
        keccak256(abi.encode(subIdAllowancesHashes))
      )
    );
  }

  function _hashAssetAllowance(IAllowances.AssetAllowance memory allowance) private pure returns (bytes32) {
    return keccak256(abi.encode(ASSET_ALLOWANCE_TYPEHASH, allowance));
  }

  function _hashSubIdAllowance(IAllowances.SubIdAllowance memory allowance) private pure returns (bytes32) {
    return keccak256(abi.encode(SUBID_ALLOWANCE_TYPEHASH, allowance));
  }
}
