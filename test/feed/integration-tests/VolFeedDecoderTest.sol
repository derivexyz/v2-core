// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../src/periphery/CompressedSubmitter.sol";
import "../../../src/periphery/VolFeedDecoder.sol";
import "../../../src/feeds/LyraSpotFeed.sol";
import "../../../src/feeds/LyraVolFeed.sol";


import "../unit-tests/LyraFeedTestUtils.sol";
import "./CompressedDataUtils.t.sol";

import {IBaseManager} from "../../../src/interfaces/IBaseManager.sol";

contract VolFeedDecoderTest is LyraFeedTestUtils, CompressedDataUtils {
  uint pk = 0xBEEF;

  CompressedSubmitter submitter;
  LyraSpotFeed spotFeed;
  LyraVolFeed volFeed;
  VolFeedDecoder decoder;

  uint8 spotFeedId = 1;
  uint8 volFeedId = 2;

  function setUp() public {
    submitter = new CompressedSubmitter();
    spotFeed = new LyraSpotFeed();
    volFeed = new LyraVolFeed();
    decoder = new VolFeedDecoder();

    spotFeed.addSigner(vm.addr(pk), true);
    volFeed.addSigner(vm.addr(pk), true);

    // spot feed has no decoder
    submitter.registerFeedIds(spotFeedId, address(spotFeed), address(0));

    submitter.registerFeedIds(volFeedId, address(volFeed), address(decoder));
  }

  function testSubmitBatchData() public {
    // prepare raw data
    // IBaseLyraFeed.FeedData memory spotData1 = _getDefaultSpotData();

    // bytes memory data1 = _transformToCompressedFeedData(_signFeedData(spotFeed1, pk, spotData1));

    // IBaseLyraFeed.FeedData memory spotData2 = _getDefaultSpotData();
    // bytes memory data2 = _transformToCompressedFeedData(_signFeedData(spotFeed2, pk, spotData2));

    // uint32 data1Length = uint32(data1.length);
    // uint32 data2Length = uint32(data2.length);

    // uint8 numOfFeeds = 1;

    // bytes[] memory managerDatas = new bytes[](2);
    // bytes memory compressedData = abi.encodePacked(numOfFeeds, spotFeedId, data1Length, data1);

    // console2.log("final compressed data length", compressedData.length);

    // submitter.acceptData(compressedData);

    // (uint spot1, uint confidence1) = spotFeed.getSpot();
    // (uint spot2, uint confidence2) = spotFeed.getSpot();

    // assertEq(spot1, 1000e18);
    // assertEq(confidence1, 1e18);

    // assertEq(spot2, 1000e18);
    // assertEq(confidence2, 1e18);
  }

}
