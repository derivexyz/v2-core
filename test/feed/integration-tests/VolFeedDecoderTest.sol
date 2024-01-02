// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "../../../src/periphery/CompressedSubmitter.sol";
import "../../../src/periphery/VolFeedDecoder.sol";
import "../../../src/feeds/LyraVolFeed.sol";

import "../unit-tests/LyraFeedTestUtils.sol";
import "./CompressedDataUtils.t.sol";

import "forge-std/console2.sol";

contract VolFeedDecoderTest is LyraFeedTestUtils, CompressedDataUtils {
  uint pk = 0xBEEF;

  CompressedSubmitter submitter;
  LyraVolFeed volFeed;
  VolFeedDecoder decoder;

  uint8 volFeedId = 1;

  uint64 defaultExpiry = uint64(block.timestamp + 180 days);

  function setUp() public {
    submitter = new CompressedSubmitter();
    volFeed = new LyraVolFeed();
    decoder = new VolFeedDecoder();

    volFeed.addSigner(vm.addr(pk), true);

    submitter.registerFeedIds(volFeedId, address(volFeed), address(decoder));
  }

  function testSubmitCompressedVolData() public {
    // prepare raw data
    IBaseLyraFeed.FeedData memory volData = _getDefaultVolData();

    // sign the original format, and encode back to bytes
    bytes memory signedBytes = _signFeedData(volFeed, pk, volData);

    // decode the bytes, compress the data field, and encode back to bytes
    bytes memory data = _transformToCompressedFeedData(_compressFeedData(signedBytes));

    uint32 dataLength = uint32(data.length);

    uint8 numOfFeeds = 1;

    bytes memory compressedData = abi.encodePacked(numOfFeeds, volFeedId, dataLength, data);

    submitter.acceptData(compressedData);

    (uint vol, uint confidence) = volFeed.getVol(uint128(uint(1500e18)), defaultExpiry);
    assertApproxEqAbs(vol, 1.1728e18, 0.0001e18);
    assertEq(confidence, 1e18);
  }

  function _getDefaultVolData() internal view returns (IBaseLyraFeed.FeedData memory) {
    int SVI_a = 1e18;
    uint SVI_b = 1.5e18;
    int SVI_rho = -0.1e18;
    int SVI_m = -0.05e18;
    uint SVI_sigma = 0.05e18;
    uint SVI_fwd = 1200e18;
    uint64 SVI_refTau = 1e18; // 1 year
    uint64 confidence = 1e18;

    // constructed in the legacy way: not compressed
    bytes memory volData =
      abi.encode(defaultExpiry, SVI_a, SVI_b, SVI_rho, SVI_m, SVI_sigma, SVI_fwd, SVI_refTau, confidence);

    return IBaseLyraFeed.FeedData({
      data: volData,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
  }

  /// @dev take the "FeedData" bytes, decode, compressed the "data" field according to the new format, and encode back to "FeedData" -> bytes
  function _compressFeedData(bytes memory feedDataInput) internal pure returns (bytes memory) {
    IBaseLyraFeed.FeedData memory input = abi.decode(feedDataInput, (IBaseLyraFeed.FeedData));

    (
      uint64 expiry,
      int SVI_a,
      uint SVI_b,
      int SVI_rho,
      int SVI_m,
      uint SVI_sigma,
      uint SVI_fwd,
      uint64 SVI_refTau,
      uint64 confidence
    ) = abi.decode(input.data, (uint64, int, uint, int, int, uint, uint, uint64, uint64));

    // override with new data (packed)
    input.data = abi.encodePacked(
      uint64(expiry),
      int80(SVI_a),
      uint80(SVI_b),
      int80(SVI_rho),
      int80(SVI_m),
      uint80(SVI_sigma),
      uint96(SVI_fwd),
      uint64(SVI_refTau),
      uint64(confidence)
    );

    return abi.encode(input);
  }
}
