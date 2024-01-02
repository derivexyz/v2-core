// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../src/periphery/CompressedSubmitter.sol";
import "../../../src/feeds/LyraSpotFeed.sol";
import "../unit-tests/LyraFeedTestUtils.sol";
import {IBaseManager} from "../../../src/interfaces/IBaseManager.sol";

contract CompressedSubmitterTest is LyraFeedTestUtils {
  uint pk = 0xBEEF;

  CompressedSubmitter submitter;
  LyraSpotFeed spotFeed1;
  LyraSpotFeed spotFeed2;

  uint8 feedId1 = 1;
  uint8 feedId2 = 2;

  function setUp() public {
    submitter = new CompressedSubmitter();
    spotFeed1 = new LyraSpotFeed();
    spotFeed2 = new LyraSpotFeed();

    spotFeed1.addSigner(vm.addr(pk), true);
    spotFeed2.addSigner(vm.addr(pk), true);

    submitter.registerFeedIds(feedId1, address(spotFeed1), address(0));
    submitter.registerFeedIds(feedId2, address(spotFeed2), address(0));
  }

  function testSubmitBatchData() public {
    // prepare raw data
    IBaseLyraFeed.FeedData memory spotData1 = _getDefaultSpotData();

    bytes memory data1 = _transformToCompressedFeedData(_signFeedData(spotFeed1, pk, spotData1));

    IBaseLyraFeed.FeedData memory spotData2 = _getDefaultSpotData();
    bytes memory data2 = _transformToCompressedFeedData(_signFeedData(spotFeed2, pk, spotData2));

    uint32 data1Length = uint32(data1.length);
    uint32 data2Length = uint32(data2.length);

    uint8 numOfFeeds = 2;

    // bytes[] memory managerDatas = new bytes[](2);
    bytes memory compressedData = abi.encodePacked(numOfFeeds, feedId1, data1Length, data1, feedId2, data2Length, data2);

    // console2.log("final compressed data length", compressedData.length);

    submitter.acceptData(compressedData);

    (uint spot1, uint confidence1) = spotFeed1.getSpot();
    (uint spot2, uint confidence2) = spotFeed2.getSpot();

    assertEq(spot1, 1000e18);
    assertEq(confidence1, 1e18);

    assertEq(spot2, 1000e18);
    assertEq(confidence2, 1e18);
  }

  function testRegisterFeedIds() public {
    submitter.registerFeedIds(1, address(spotFeed1), address(0));
    submitter.registerFeedIds(2, address(spotFeed2), address(1));

    (address _feed, address _decoder) = submitter.feeds(1);
    assertEq(_feed, address(spotFeed1));
    assertEq(_decoder, address(0));

    (_feed, _decoder) = submitter.feeds(2);
    assertEq(_feed, address(spotFeed2));
    assertEq(_decoder, address(1));
  }

  function _getDefaultSpotData() internal view returns (IBaseLyraFeed.FeedData memory) {
    uint96 price = 1000e18;
    uint64 confidence = 1e18;
    bytes memory spotData = abi.encode(price, confidence);
    return IBaseLyraFeed.FeedData({
      data: spotData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
  }

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
