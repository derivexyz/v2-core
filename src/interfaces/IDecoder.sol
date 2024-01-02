// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

/**
 * @dev This contract is used with CompressedSubmitter to decode the compressed feed data
 */
interface IDecoder {
  /**
   * @notice decode the compressed byte data and return the original bytes data that can be processed by the feeds
   */
  function decode(bytes calldata data) external view returns (bytes memory);
}
