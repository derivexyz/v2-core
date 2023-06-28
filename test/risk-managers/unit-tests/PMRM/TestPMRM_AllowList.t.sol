pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "src/risk-managers/PMRM.sol";
import "src/SubAccounts.sol";
import {IBaseManager} from "src/interfaces/IBaseManager.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";

import "test/shared/mocks/MockFeeds.sol";

import "test/shared/mocks/MockFeeds.sol";

import "test/risk-managers/unit-tests/PMRM/utils/PMRMSimTest.sol";
import "src/feeds/AllowList.sol";

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
    IAllowList.AllowListData memory allowListData = IAllowList.AllowListData({
      user: user,
      allowed: allowed,
      timestamp: uint64(timestamp),
      deadline: block.timestamp + 5,
      signer: signer,
      signature: new bytes(0)
    });
    bytes32 structHash = allowList.hashAllowListData(allowListData);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPK, ECDSA.toTypedDataHash(allowList.domainSeparator(), structHash));
    allowListData.signature = bytes.concat(r, s, bytes1(v));
    allowList.acceptData(abi.encode(allowListData));
  }
}
