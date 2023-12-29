// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import "../interfaces/IBaseManager.sol";
import "../interfaces/IDataReceiver.sol";

import "../interfaces/IBaseLyraFeed.sol";

import "forge-std/console2.sol";

contract CompressedSubmitter is IDataReceiver, Ownable2Step {
  /// @dev id to feed address
  mapping(uint8 => address) public feedIds;

  /// @dev id to signer address
  mapping(uint8 => address) public signers;

  event FeedIdRegistered(uint8 id, address feed);

  event SignerRegistered(uint8 id, address signer);

  /**
   * @dev submit compressed data directly (not through the manager)
   */
  function submitCompressedData(bytes calldata data) external {
    IBaseManager.ManagerData[] memory feedDatas = _parseCompressedToFeedDatas(data);

    for (uint i; i < feedDatas.length; i++) {
      IDataReceiver(feedDatas[i].receiver).acceptData(feedDatas[i].data);
    }
  }

  /**
   * @dev used as an "un-wrapper" for manager data to submit through the manager.
   *      Data is compressed into bytes
   */
  function acceptData(bytes calldata data) external {
    IBaseManager.ManagerData[] memory feedDatas = _parseCompressedToFeedDatas(data);

    for (uint i; i < feedDatas.length; i++) {
      IDataReceiver(feedDatas[i].receiver).acceptData(feedDatas[i].data);
    }
  }

  /**
   * Map ids to feed addresses
   */
  function registerFeedIds(uint8 id, address feed) external onlyOwner {
    feedIds[id] = feed;

    emit FeedIdRegistered(id, feed);
  }

  function registerSigners(uint8 id, address signer) external onlyOwner {
    signers[id] = signer;

    emit FeedIdRegistered(id, signer);
  }

  function _parseCompressedToFeedDatas(bytes calldata data) internal returns (IBaseManager.ManagerData[] memory) {
    // first byte of each byte array is number of feeds
    uint8 numFeeds = sliceUint8(data, 1);

    IBaseManager.ManagerData[] memory feedDatas = new IBaseManager.ManagerData[](numFeeds);

    // how many bytes have been "used"
    uint offset = 1;

    for (uint i; i < numFeeds; i++) {
      // 1 bytes of ID
      uint8 feedId = sliceUint8(data, offset + 1);

      // 4 bytes of data length
      bytes calldata lengthData = data[offset + 1:offset + 5];
      uint length = bytesToUint(lengthData);

      // [length] bytes of data
      bytes calldata rawFeedData = data[offset + 5:offset + 5 + length];

      feedDatas[i] = IBaseManager.ManagerData({receiver: feedIds[feedId], data: buildFeedDataFromRaw(rawFeedData)});

      offset += 5 + length;
    }

    return feedDatas;
  }

  /**
   * The raw feed data doesn't have signer addresses encoded, so here we attach them, and build FeedData struct
   * Parse the following bytes format
   *    4        bytes: length of data (uint32) --> l
   *   [l]       bytes: data;
   *    8        bytes: deadline (uint64)
   *    8        bytes: timestamp (uint64)
   *    1        byte: number of signers (uint8) --> k
   *  [20 x k]   bytes address[] signers;
   *  [65 x k]   bytes[] signatures;
   */
  function buildFeedDataFromRaw(bytes calldata data) internal view returns (bytes memory) {
    IBaseLyraFeed.FeedData memory feedData;

    uint offset = 0;

    // 4 bytes of data length
    uint length = bytesToUint(data[offset:offset + 4]);
    offset += 4;

    // [length] bytes of data
    feedData.data = data[offset:offset + length];
    offset += length;

    // 8 bytes of deadline
    feedData.deadline = uint64(bytesToUint(data[offset:offset + 8]));
    offset += 8;

    // 8 bytes of timestamp
    feedData.timestamp = uint64(bytesToUint(data[offset:offset + 8]));
    offset += 8;

    {
      // 1 byte of number of signers
      uint8 numSigners = uint8(bytesToUint(data[offset:offset + 1]));
      offset += 1;

      // [20 x k] bytes address[] signers;
      address[] memory _signers = new address[](numSigners);
      for (uint i; i < numSigners; i++) {
        bytes calldata signerIdData = data[offset:offset + 20];
        _signers[i] = address(uint160(bytesToUint(signerIdData)));
        offset += 20;
      }
      feedData.signers = _signers;

      // [65 x k] bytes[] signatures;
      bytes[] memory signatures = new bytes[](numSigners);
      for (uint i; i < numSigners; i++) {
        bytes calldata signatureData = data[offset:offset + 65];
        signatures[i] = signatureData;
        offset += 65;
      }

      feedData.signatures = signatures;
    }
    return abi.encode(feedData);
  }

  /// read a single byte and return it as a uint8
  function sliceUint8(bytes memory bs, uint location) internal pure returns (uint8 x) {
    assembly {
      x := mload(add(bs, location))
    }
  }

  function bytesToUint(bytes memory b) internal pure returns (uint num) {
    for (uint i = 0; i < b.length; i++) {
      num = num + uint(uint8(b[i])) * (2 ** (8 * (b.length - (i + 1))));
    }
  }
}
