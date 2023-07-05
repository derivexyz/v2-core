// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/feeds/BaseLyraFeed.sol";

import "forge-std/Test.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract LyraFeedTestUtils is Test {
  function _signFeedData(IBaseLyraFeed feed, uint privateKey, IBaseLyraFeed.FeedData memory feedData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 structHash = hashFeedData(feed, feedData);
    bytes32 domainSeparator = feed.domainSeparator();
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    feedData.signature = bytes.concat(r, s, bytes1(v));

    return abi.encode(feedData);
  }

  function hashFeedData(IBaseLyraFeed feed, IBaseLyraFeed.FeedData memory feedData) public view returns (bytes32) {
    bytes32 typeHash = feed.FEED_DATA_TYPEHASH();
    return keccak256(abi.encode(typeHash, feedData.data, feedData.deadline, feedData.timestamp, feedData.signer));
  }
}
