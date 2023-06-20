pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../../src/risk-managers/PMRM.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";
import {IManager} from "../../../../src/interfaces/IManager.sol";
import {IAsset} from "../../../../src/interfaces/IAsset.sol";
import {ISubAccounts} from "../../../../src/interfaces/ISubAccounts.sol";

import "../../../shared/mocks/MockManager.sol";
import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockAsset.sol";
import "../../../shared/mocks/MockOption.sol";
import "../../../shared/mocks/MockSM.sol";
import "../../../shared/mocks/MockFeeds.sol";

import "../../../risk-managers/mocks/MockDutchAuction.sol";
import "../../../shared/utils/JsonMechIO.sol";

import "../../../shared/mocks/MockFeeds.sol";
import "../../../../src/assets/WrappedERC20Asset.sol";
import "../../../shared/mocks/MockPerp.sol";

import "../../../risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";
import "../../../../src/feeds/AllowList.sol";

import "forge-std/console2.sol";

contract UNIT_TestPMRM_AllowList is PMRMSimTest {
  AllowList allowList;
  uint private signerPK;
  address private signer;

  function setUp() public override {
    super.setUp();
    signerPK = 0xBEEF;
    signer = vm.addr(signerPK);

    allowList = new AllowList();
    pmrm.setAllowList(allowList);
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
      signer: signer,
      signature: new bytes(0)
    });
    allowList.acceptData(_signFeedData(signerPK, allowListData));
  }

  function _signFeedData(uint privateKey, IBaseLyraFeed.FeedData memory feedData) internal view returns (bytes memory) {
    bytes32 structHash = hashFeedData(feedData);
    bytes32 domainSeparator = allowList.domainSeparator();
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
    feedData.signature = bytes.concat(r, s, bytes1(v));

    return abi.encode(feedData);
  }

  function hashFeedData(IBaseLyraFeed.FeedData memory feedData) public view returns (bytes32) {
    bytes32 typeHash = allowList.FEED_DATA_TYPEHASH();
    return keccak256(abi.encode(typeHash, feedData.data, feedData.deadline, feedData.timestamp, feedData.signer));
  }
}
