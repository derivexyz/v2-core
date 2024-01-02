// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../src/interfaces/IBaseLyraFeed.sol";

abstract contract CompressedDataUtils {
  /**
   * Convert abi encoded bytes to the following format:
   *
   *    4        bytes: length of data (uint32) --> l
   *   [l]       bytes: data;
   *    8        bytes: deadline (uint64)
   *    8        bytes: timestamp (uint64)
   *    1        byte:  number of signers (uint8) --> k
   *    [20 x k] bytes  signers addresses;
   *    [65 x k] bytes: signatures;
   */
  function _transformToCompressedFeedData(bytes memory data) internal pure returns (bytes memory) {
    IBaseLyraFeed.FeedData memory feedData = abi.decode(data, (IBaseLyraFeed.FeedData));
    uint32 length = uint32(feedData.data.length);
    uint8 numOfSigners = uint8(feedData.signers.length);

    // put all signers addresses into a single bytes array (20 bytes each)
    bytes memory signers = new bytes(numOfSigners * 20);
    for (uint i; i < numOfSigners; i++) {
      for (uint j; j < 20; j++) {
        signers[i * 20 + j] = bytes20(feedData.signers[i])[j];
      }
    }

    // put all signatures into a single bytes array (65 bytes each)
    bytes memory signatures = new bytes(numOfSigners * 65);

    for (uint i; i < numOfSigners; i++) {
      bytes memory signature = feedData.signatures[i];
      for (uint j; j < signature.length; j++) {
        signatures[i * 65 + j] = signature[j];
      }
    }

    bytes memory compressedData = abi.encodePacked(
      length,
      feedData.data,
      uint64(feedData.deadline),
      uint64(feedData.timestamp),
      uint8(feedData.signers.length),
      signers,
      signatures
    );

    return compressedData;
  }
}
