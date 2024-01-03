// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import "../interfaces/IBaseManager.sol";
import "../interfaces/IDataReceiver.sol";
import "../interfaces/IBaseLyraFeed.sol";
import "../interfaces/IDecoder.sol";

contract CompressedSubmitter is IDataReceiver, Ownable2Step {
  struct FeedInfo {
    address feed;
    address decoder;
  }

  /// @dev id to feed and decoder address
  mapping(uint8 => FeedInfo) public feeds;

  event FeedIdRegistered(uint8 id, address feed, address decoder);

  /**
   * @dev used as a "proxy" to handle compressed managerData, decode them, and encode properly and relay to each feeds.
   * @param data compressed managerData
   */
  function acceptData(bytes calldata data) external {
    IBaseManager.ManagerData[] memory feedDatas = _parseCompressedToFeedDatas(data);

    for (uint i; i < feedDatas.length; i++) {
      IDataReceiver(feedDatas[i].receiver).acceptData(feedDatas[i].data);
    }
  }

  /**
   * @dev register an ID for a feed addresses
   */
  function registerFeedIds(uint8 id, address feed, address decoder) external onlyOwner {
    feeds[id] = FeedInfo(feed, decoder);

    emit FeedIdRegistered(id, feed, decoder);
  }

  /**
   *  Parse the following bytes format
   *    1        byte:  num of feeds
   *
   *   ---       Each Feed Data      -----
   *
   *    1        byte:  feed ID
   *    4        bytes: raw feedData length  -> l
   *   [l]       bytes: raw feedData
   */
  function _parseCompressedToFeedDatas(bytes calldata data) internal view returns (IBaseManager.ManagerData[] memory) {
    // first byte of each byte array is number of feeds
    uint offset = 0;

    uint8 numFeeds = uint8(bytes1(data[offset:offset + 1]));
    offset += 1;

    IBaseManager.ManagerData[] memory feedDatas = new IBaseManager.ManagerData[](numFeeds);

    for (uint i; i < numFeeds; i++) {
      // 1 bytes of ID
      uint8 feedId = uint8(bytes1(data[offset:offset + 1]));
      offset += 1;

      // 4 bytes of data length
      uint length = uint32(bytes4(data[offset:offset + 4]));
      offset += 4;

      // [length] bytes of data
      bytes calldata rawFeedData = data[offset:offset + length];
      offset += length;

      feedDatas[i] =
        IBaseManager.ManagerData({receiver: feeds[feedId].feed, data: _buildFeedDataFromRaw(feedId, rawFeedData)});
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
   *  [20 x k]   bytes: k signer addresses
   *  [65 x k]   bytes: k signatures
   */
  function _buildFeedDataFromRaw(uint8 feedId, bytes calldata data) internal view returns (bytes memory) {
    IBaseLyraFeed.FeedData memory feedData;

    uint offset = 0;

    // 4 bytes of data length
    uint length = uint32(bytes4(data[offset:offset + 4]));
    offset += 4;

    // [length] bytes of data
    feedData.data = data[offset:offset + length];
    offset += length;

    if (feeds[feedId].decoder != address(0)) {
      feedData.data = IDecoder(feeds[feedId].decoder).decode(feedData.data);
    }

    // 8 bytes of deadline
    feedData.deadline = uint64(bytes8(data[offset:offset + 8]));
    offset += 8;

    // 8 bytes of timestamp
    feedData.timestamp = uint64(bytes8(data[offset:offset + 8]));
    offset += 8;

    {
      // 1 byte of number of signers
      uint8 numSigners = uint8(bytes1(data[offset:offset + 1]));
      offset += 1;

      // [20 x k] bytes of signer addresses;
      address[] memory _signers = new address[](numSigners);
      for (uint i; i < numSigners; i++) {
        _signers[i] = address(uint160(bytes20(data[offset:offset + 20])));
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
}
