// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./LyraFeedTestUtils.sol";

import "../../../src/feeds/LyraSpotFeed.sol";
import "../../../src/feeds/AllowList.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_AllowList is LyraFeedTestUtils {
  AllowList feed;

  // signer
  uint private pk;
  address private pkOwner;
  address private defaultUser = address(0x1234);

  function setUp() public {
    feed = new AllowList();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    feed.addSigner(pkOwner, true);
  }

  function testCanAddSigner() public {
    address alice = address(0xaaaa);
    feed.addSigner(alice, true);
    assertEq(feed.isSigner(alice), true);
  }

  function testCanPassInDataAndUpdateAllowList() public {
    // by default with allowlist disabled, returns true for every user
    assertEq(feed.canTrade(defaultUser), true);

    feed.setAllowListEnabled(true);
    assertEq(feed.canTrade(defaultUser), false);

    IBaseLyraFeed.FeedData memory allowListData = _getDefaultAllowListData();
    bytes memory data = _signFeedData(feed, pk, allowListData);

    feed.acceptData(data);

    assertEq(feed.canTrade(defaultUser), true);
  }

  function testCanTradeStates() public {
    feed.setAllowListEnabled(true);

    IBaseLyraFeed.FeedData memory allowListData = _getDefaultAllowListData();
    allowListData.timestamp = uint64(block.timestamp - 10);

    feed.acceptData(_signFeedData(feed, pk, allowListData));

    allowListData.data = abi.encode(defaultUser, false);
    feed.acceptData(_signFeedData(feed, pk, allowListData));

    assertEq(feed.canTrade(defaultUser), true);

    allowListData.timestamp = uint64(block.timestamp);
    feed.acceptData(_signFeedData(feed, pk, allowListData));

    assertEq(feed.canTrade(defaultUser), false);
  }

  function _getDefaultAllowListData() internal view returns (IBaseLyraFeed.FeedData memory allowListData) {
    return IBaseLyraFeed.FeedData({
      data: abi.encode(defaultUser, true),
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }
}
