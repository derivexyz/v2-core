pragma solidity ^0.8.18;

import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";
import {IBaseManager} from "../../../../src/interfaces/IBaseManager.sol";

import "../../../../src/risk-managers/PMRM.sol";
import "../../../../src/SubAccounts.sol";

import "../../../shared/mocks/MockFeeds.sol";

import "../../../shared/mocks/MockFeeds.sol";

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";
import "../../../../src/feeds/AllowList.sol";

contract UNIT_TestPMRM_AllowList is PMRMSimTest {
  AllowList allowList;
  uint private signerPK;
  address private signer;

  function setUp() public override {
    super.setUp();
    signerPK = 0xBEEF;
    signer = vm.addr(signerPK);

    allowList = new AllowList();
    viewer.setAllowList(allowList);
    allowList.addSigner(signer, true);
    allowList.setAllowListEnabled(true);
  }

  function testPMRM_blocksTradesForNonAllowListedUsers() public {
    pmrm.setTrustedRiskAssessor(alice, true);

    ISubAccounts.AssetBalance[] memory balances = setupTestScenarioAndGetAssetBalances(".BigOne");

    vm.expectRevert(IBaseManager.BM_CannotTrade.selector);
    cash.deposit(bobAcc, 200_000 ether);

    setAllowListed(bob, true, block.timestamp - 5);
    // once bob is allowlisted, his account can be deposited to
    _depositCash(bobAcc, 200_000 ether);

    vm.startPrank(bob);
    subAccounts.setApprovalForAll(alice, true);
    vm.startPrank(alice);
    ISubAccounts.AssetTransfer[] memory transfers = _getTransferBatch(aliceAcc, bobAcc, balances);

    // now that alice can't trade, it reverts
    vm.expectRevert(IBaseManager.BM_CannotTrade.selector);
    subAccounts.submitTransfers(transfers, "");

    // alice can submit the signature so no need to undo prank
    setAllowListed(alice, true, block.timestamp - 5);

    // now that alice can trade, it doesn't revert
    subAccounts.submitTransfers(transfers, "");
  }

  function testPMRM_forceWithdraw() public {
    // since bob has no assets, it will revert (only accounts with only positive cash balances can get force withdrawn)
    vm.expectRevert(IBaseManager.BM_InvalidForceWithdrawAccountState.selector);
    pmrm.forceWithdrawAccount(bobAcc);

    allowList.setAllowListEnabled(false);
    _depositCash(bobAcc, 200_000 ether);

    vm.expectRevert(IBaseManager.BM_OnlyBlockedAccounts.selector);
    pmrm.forceWithdrawAccount(bobAcc);

    allowList.setAllowListEnabled(true);
    pmrm.forceWithdrawAccount(bobAcc);
  }

  function setAllowListed(address user, bool allowed, uint timestamp) internal {
    IBaseLyraFeed.FeedData memory allowListData = IBaseLyraFeed.FeedData({
      data: abi.encode(user, allowed),
      timestamp: uint64(timestamp),
      deadline: block.timestamp + 5,
      signers: new address[](1),
      signatures: new bytes[](1)
    });
    allowList.acceptData(_signFeedData(signerPK, allowListData));
  }

  function _signFeedData(uint privateKey, IBaseLyraFeed.FeedData memory feedData) internal view returns (bytes memory) {
    bytes32 structHash = hashFeedData(feedData);
    bytes32 domainSeparator = allowList.domainSeparator();
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    feedData.signatures[0] = bytes.concat(r, s, bytes1(v));
    feedData.signers[0] = vm.addr(privateKey);
    return abi.encode(feedData);
  }

  function hashFeedData(IBaseLyraFeed.FeedData memory feedData) public view returns (bytes32) {
    bytes32 typeHash = allowList.FEED_DATA_TYPEHASH();
    return keccak256(abi.encode(typeHash, feedData.data, feedData.deadline, feedData.timestamp));
  }
}
