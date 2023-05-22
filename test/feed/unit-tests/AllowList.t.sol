// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/feeds/LyraSpotFeed.sol";
import "../../../src/feeds/AllowList.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_AllowList is Test {
  AllowList feed;

  bytes32 domainSeparator;

  // signer
  uint private pk;
  address private pkOwner;
  address private defaultUser = address(0x1234);

  function setUp() public {
    feed = new AllowList();
    domainSeparator = feed.domainSeparator();

    // set signer
    pk = 0xBEEF;
    pkOwner = vm.addr(pk);

    vm.warp(block.timestamp + 365 days);
    feed.addSigner(pkOwner, true);
  }

  function testDomainSeparator() public {
    assertEq(feed.domainSeparator(), domainSeparator);
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

    IAllowList.AllowListData memory allowListData = _getDefaultAllowListData();
    bytes memory data = _getSignedAllowListData(pk, allowListData);

    feed.acceptData(data);

    assertEq(feed.canTrade(defaultUser), true);
  }

  function test() public {
    feed.setAllowListEnabled(true);

    IAllowList.AllowListData memory allowListData = _getDefaultAllowListData();
    allowListData.timestamp = uint64(block.timestamp - 10);

    feed.acceptData(_getSignedAllowListData(pk, allowListData));

    allowListData.allowed = false;
    feed.acceptData(_getSignedAllowListData(pk, allowListData));

    assertEq(feed.canTrade(defaultUser), true);

    allowListData.timestamp = uint64(block.timestamp);
    feed.acceptData(_getSignedAllowListData(pk, allowListData));

    assertEq(feed.canTrade(defaultUser), false);
  }

  function _getDefaultAllowListData() internal view returns (IAllowList.AllowListData memory allowListData) {
    return IAllowList.AllowListData({
      user: defaultUser,
      allowed: true,
      timestamp: uint64(block.timestamp),
      deadline: block.timestamp + 5,
      signer: pkOwner,
      signature: new bytes(0)
    });
  }

  function _getSignedAllowListData(uint privateKey, IAllowList.AllowListData memory allowListData)
    internal
    view
    returns (bytes memory data)
  {
    allowListData.signature = _signAllowListData(privateKey, allowListData);
    return abi.encode(allowListData);
  }

  function _signAllowListData(uint privateKey, IAllowList.AllowListData memory allowListData)
    internal
    view
    returns (bytes memory)
  {
    bytes32 structHash = feed.hashAllowListData(allowListData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
