// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "openzeppelin/access/Ownable2Step.sol";
import "../interfaces/IBaseManager.sol";
import "../interfaces/IDataReceiver.sol";

import "forge-std/console2.sol";

contract CompressedSubmitter is IDataReceiver, Ownable2Step {
  mapping(uint8 => address) public feedIds;

  event FeedIdRegistered(uint8 id, address feed);

  /**
   * @dev submit compressed data directly (not through the manager)
   */
  function submitCompressedData(bytes calldata data) external {
    IBaseManager.ManagerData[] memory feedDatas = _parseFeedDataArray(data);

    for (uint i; i < feedDatas.length; i++) {
      IDataReceiver(feedDatas[i].receiver).acceptData(feedDatas[i].data);
    }
  }

  /**
   * @dev used as an "un-wrapper" for manager data to submit through the manager.
   *      Data is compressed into bytes
   */
  function acceptData(bytes calldata data) external {
    IBaseManager.ManagerData[] memory feedDatas = _parseFeedDataArray(data);

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

  function _parseFeedDataArray(bytes calldata data) internal returns (IBaseManager.ManagerData[] memory) {
    bytes memory data2 = data[0:1];
    console2.logBytes(data2);

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
      bytes calldata feedData = data[offset + 5:offset + 5 + length];

      feedDatas[i] = IBaseManager.ManagerData({receiver: feedIds[feedId], data: feedData});

      offset += 5 + length;
    }

    return feedDatas;
  }

  /// read a single byte and return it as a uint8
  function sliceUint8(bytes memory bs, uint location) internal pure returns (uint8 x) {
    assembly {
      x := mload(add(bs, location))
    }
  }

  // read 4 bytes and return as uint32
  function sliceUint32(bytes memory bs, uint location) internal pure returns (uint32 x) {
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
