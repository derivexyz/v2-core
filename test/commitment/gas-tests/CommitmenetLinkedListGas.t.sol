// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/commitments/CommitmentLinkedList.sol";
import "src/Account.sol";

import "../../account/mocks/managers/DumbManager.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockManager.sol";

import "test/account/mocks/assets/lending/Lending.sol";
import "test/account/mocks/assets/lending/ContinuousJumpRateModel.sol";

contract CommitmentLinkedListGas is Script {
  uint ownAcc;
  CommitmentLinkedList commitment;

  uint expiry;
  uint96 subId = 1;

  MockManager dumbManager;
  MockERC20 usdc;
  Lending usdcAsset;
  MockAsset optionAsset;

  Account account;
  uint accId;

  uint16 constant commitmentWeight = 1;

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    // gas tests

    uint gasBefore = gasleft();
    commitment.register();
    uint gasAfter = gasleft();
    console.log("gas register", gasBefore - gasAfter);

    // regisger for others
    _registerUsers(500);

    gasBefore = gasleft();
    commitment.deposit(6_000_000 * 1e18);
    gasAfter = gasleft();
    console.log("gas deposit", gasBefore - gasAfter);

    gasBefore = gasleft();
    commitment.commit(subId, 90, 100, commitmentWeight); // collecting: 1, pending: 0
    gasAfter = gasleft();
    console.log("gas commit: #1 for subId", gasBefore - gasAfter);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    console2.log("----------------------------------");

    uint gasAdd50SameUser = _commitMultipleSubIds(50, 50);
    console.log("gas commitMultiple: first user to commit to 50 subId.", gasAdd50SameUser);

    vm.warp(block.timestamp + 20 minutes);
    gasBefore = gasleft();
    commitment.checkRollover();
    gasAfter = gasleft();
    console.log("gas rollover 50 subIds, 1 vol each", gasBefore - gasAfter);

    console2.log("----------------------------------");

    // add 50 commits to same subId
    uint gasSamId50Users = _commitBatchFromDiffUsers(50, 1, 0, 0); // bid offset: 0, user offset: 0
    console.log("gas commitBatchOnBehalf: 50 quotes from 50 users on same subId", gasSamId50Users);

    // add to the end of the linked list
    gasBefore = gasleft();
    commitment.commit(0, 200, 220, commitmentWeight);
    gasAfter = gasleft();
    console.log("gas commit: 51st in linked list", gasBefore - gasAfter);

    vm.warp(block.timestamp + 20 minutes);
    gasBefore = gasleft();
    commitment.checkRollover();
    gasAfter = gasleft();
    console.log("gas rollover 1 subIds", gasBefore - gasAfter);

    console2.log("----------------------------------");

    // user 0 ~ 50 commit to 50 subIds
    uint gasAdd50SubIds = _commitBatchFromDiffUsers(50, 50, 0, 0); // bid offset: 0, user offset: 0
    console.log("gas commitBatchOnBehalf: 50 quotes from 50 users to 50 subIds:", gasAdd50SubIds);

    gasAdd50SameUser = _commitMultipleSubIds(50, 0);
    console.log("gas commitMultiple: second user to commit to 50 subId, same vol", gasAdd50SameUser);

    // user 50 ~ 100 commit to 50 subIds
    gasAdd50SubIds = _commitBatchFromDiffUsers(50, 50, 0, 50);
    console.log("gas commitBatchOnBehalf: 50 quotes from 50 users to same subId, diff vol:", gasAdd50SubIds);

    vm.warp(block.timestamp + 20 minutes);
    gasBefore = gasleft();
    commitment.checkRollover();
    gasAfter = gasleft();
    console.log("gas rollover 50 subIds, 3 vol each", gasBefore - gasAfter);

    console2.log("----------------------------------");

    // user 0 ~ 50 commit to 50 subIds
    _commitBatchFromDiffUsers(50, 50, 0, 0); // bid offset: 0, user offset: 0

    gasAdd50SameUser = _commitMultipleSubIds(50, 50);
    console.log("gas commitMultiple: second user to commit to 50 subId, new vol", gasAdd50SameUser);

    vm.warp(block.timestamp + 20 minutes);
    gasBefore = gasleft();
    commitment.checkRollover();
    gasAfter = gasleft();
    console.log("gas rollover 50 subIds, 2 vol each", gasBefore - gasAfter);

    console2.log("----------------------------------");

    // user 0 ~ 50 commit to 50 subIds
    _commitBatchFromDiffUsers(50, 50, 0, 0); // bid offset: 0, user offset: 0
    // user 50 ~ 100 commit to 50 subIds
    _commitBatchFromDiffUsers(50, 50, 1, 50); // bid offset: 0, user offset: 50
    // user 100 ~ 150 commit to 50 subIds
    _commitBatchFromDiffUsers(50, 50, 2, 100); // bid offset: 0, user offset: 100
    // user 150 ~ 200 commit to 50 subIds
    _commitBatchFromDiffUsers(50, 50, 3, 150); // bid offset: 0, user offset: 150

    gasAdd50SameUser = _commitMultipleSubIds(50, 50);
    console.log("gas commitMultiple: 5th user to commit to 50 subId, same vol", gasAdd50SameUser);

    vm.warp(block.timestamp + 20 minutes);
    gasBefore = gasleft();
    commitment.checkRollover();
    gasAfter = gasleft();
    console.log("gas rollover 50 subIds, 5 vol each", gasBefore - gasAfter);
  }

  function _registerUsers(uint count) internal {
    for (uint16 i = 0; i < count; i++) {
      // register and collat
      uint privKey = i + 1;
      address user = vm.addr(privKey);

      commitment.registerAndDepositFor(user, 10000 * 1e18);
    }
  }

  function _commitBatchFromDiffUsers(uint total, uint subIdCount, uint16 quoteoffSet, uint16 userOffset)
    internal
    returns (uint gasCost)
  {
    CommitmentLinkedList.QuoteCommitment[] memory quotes = new CommitmentLinkedList.QuoteCommitment[](total);
    CommitmentLinkedList.Signature[] memory sigs = new CommitmentLinkedList.Signature[](total);
    address[] memory signers = new address[](total);

    for (uint16 i = 0; i < total; i++) {
      // register and collat
      uint privKey = i + userOffset + 1;
      address user = vm.addr(privKey);

      uint96 subId = uint96(i % subIdCount);
      uint16 bid = 50 + i + quoteoffSet;
      uint16 ask = 60 + i + quoteoffSet;

      signers[i] = user;

      uint64 nonce = 1;

      uint64 expiry = uint64(block.timestamp + 15 minutes);

      quotes[i] = CommitmentLinkedList.QuoteCommitment(subId, bid, ask, expiry, commitmentWeight, nonce);
      bytes32 quoteHash =
        keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quotes[i]))));
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, quoteHash); // alice is vm.addr(1)
      sigs[i] = CommitmentLinkedList.Signature(v, r, s);
    }

    uint gasBefore = gasleft();
    commitment.commitBatchOnBehalf(signers, quotes, sigs);
    uint gasAfter = gasleft();
    return gasBefore - gasAfter;
  }

  function _commitMultipleSubIds(uint total, uint16 offSet) internal returns (uint gasCost) {
    uint96[] memory subIds = new uint96[](total);

    uint16[] memory bids = new uint16[](total);

    uint16[] memory asks = new uint16[](total);

    uint64[] memory weights = new uint64[](total);

    // subIds all need to be different
    for (uint16 i; i < total; i++) {
      subIds[i] = i;
      bids[i] = 50 + offSet;
      asks[i] = 60 + offSet;
      weights[i] = 1;
    }

    uint gasBefore = gasleft();
    commitment.commitMultiple(subIds, bids, asks, weights);
    uint gasAfter = gasleft();
    return gasBefore - gasAfter;
  }

  function deployMockSystem() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");

    optionAsset = new MockAsset(IERC20(address(0)), IAccount(address(account)), true);

    usdc.mint(msg.sender, 50_000_000 * 1e18);

    dumbManager = new MockManager(address(account));

    ContinuousJumpRateModel interestRateModel = new ContinuousJumpRateModel(5e16, 1e17, 2e17, 5e17);
    usdcAsset = new Lending(IERC20(usdc), IAccount(address(account)), interestRateModel);
    usdcAsset.setManagerAllowed(IManager(dumbManager), true);

    commitment =
    new CommitmentLinkedList(address(account), address(usdc), address(usdcAsset), address(optionAsset), address(dumbManager));

    usdc.approve(address(commitment), type(uint).max);
    usdc.approve(address(usdcAsset), type(uint).max);

    accId = account.createAccount(msg.sender, dumbManager);
    // console2.log("accId", accId);
    account.approve(address(commitment), accId);
    usdcAsset.deposit(accId, 1_000_000 * 1e18);
  }
}
