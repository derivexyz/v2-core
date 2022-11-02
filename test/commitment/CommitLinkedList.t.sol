// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/mocks/MockERC20.sol";
import "../shared/mocks/MockAsset.sol";
import "test/account/mocks/assets/OptionToken.sol";
import "../shared/mocks/MockManager.sol";
import "../account/mocks/managers/DumbManager.sol";
import "test/account/mocks/feeds/SettlementPricer.sol";
import "test/account/mocks/feeds/PriceFeeds.sol";
import "test/account/mocks/assets/lending/Lending.sol";
import "test/account/mocks/assets/lending/ContinuousJumpRateModel.sol";
import "src/commitments/CommitmentLinkedList.sol";
import "src/Account.sol";

contract UNIT_CommitLinkedList is Test {
  CommitmentLinkedList commitment;
  uint16 constant commitmentWeight = 1;

  uint96 subId = 1;

  MockManager dumbManager;

  MockERC20 usdc;
  // MockAsset usdcAsset;
  Lending usdcAsset;
  InterestRateModel interestRateModel;
  OptionToken optionAsset;
  TestPriceFeeds priceFeeds;
  SettlementPricer settlementPricer;

  uint accId;

  Account account;

  uint alicePrivKey = 1;
  uint bobPrivKey = 2;
  uint charliePrivKey = 3;
  uint davidPrivKey = 4;
  uint edPrivKey = 5;

  address alice = vm.addr(alicePrivKey);
  address bob = vm.addr(bobPrivKey);
  address charlie = vm.addr(charliePrivKey);
  address david = vm.addr(davidPrivKey);
  address ed = vm.addr(edPrivKey);

  address random = address(0x7749);

  function setUp() public {
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    dumbManager = new DumbManager(address(account));

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");
    interestRateModel = new ContinuousJumpRateModel(5e16, 1e17, 2e17, 5e17);
    usdcAsset = new Lending(IERC20(usdc), IAccount(address(account)), interestRateModel);
    usdcAsset.setManagerAllowed(IManager(dumbManager), true);
    // usdcAsset = new Lending(IERC20(usdc), IAccount(address(account)), false);

    /* option related deploys */
    priceFeeds = new TestPriceFeeds();
    priceFeeds.setSpotForFeed(0, 1e18);
    priceFeeds.setSpotForFeed(1, 1500e18);
    settlementPricer = new SettlementPricer(PriceFeeds(priceFeeds));
    optionAsset = new OptionToken(IAccount(address(account)), priceFeeds, settlementPricer, 1);
    addListings(); // 49 listings
    optionAsset.setManagerAllowed(IManager(dumbManager), true);

    commitment =
    new CommitmentLinkedList(address(account), address(usdc), address(usdcAsset), address(optionAsset), address(dumbManager));

    uint128 oneMillion = 1_000_000e18;

    for (uint i = 0; i < 5; i++) {
      uint privKey = i + 1;
      address user = vm.addr(privKey);

      usdc.mint(user, oneMillion);

      vm.startPrank(user);
      usdc.approve(address(commitment), type(uint).max);
      usdc.approve(address(usdcAsset), type(uint).max);
      commitment.register();
      commitment.deposit(oneMillion);
      vm.stopPrank();
    }

    // give usdc to this address: (executor)
    usdc.mint(address(this), oneMillion);
    usdc.approve(address(commitment), type(uint).max);
    usdc.approve(address(usdcAsset), type(uint).max);
    commitment.register();
    // deposit into account so it can execute
    accId = account.createAccount(address(this), IManager(address(dumbManager)));
    usdcAsset.deposit(accId, oneMillion);
    // approve commitment contract to trade from my account
    account.approve(address(commitment), accId);

    vm.warp(block.timestamp + 1 days);
  }

  function testCanCommit() public {
    vm.prank(alice);
    commitment.commit(subId, 95, 105, commitmentWeight);

    vm.prank(bob);
    commitment.commit(subId, 95, 105, commitmentWeight);

    vm.prank(charlie);
    commitment.commit(subId, 97, 107, commitmentWeight);

    vm.prank(david);
    commitment.commit(subId, 100, 110, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 4);
    assertEq(commitment.collectingLength(), 0);
  }

  function testCanCommitOnBehalfOfOthers() public {
    uint64 expiry = uint64(block.timestamp + 10 minutes);

    CommitmentLinkedList.QuoteCommitment memory quote =
      CommitmentLinkedList.QuoteCommitment(subId, 95, 105, expiry, commitmentWeight, 1);
    bytes32 quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, quoteHash); // alice is vm.addr(1)
    CommitmentLinkedList.Signature memory sig = CommitmentLinkedList.Signature(v, r, s);

    commitment.commitOnBehalf(alice, quote, sig);

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 1);
    assertEq(commitment.collectingLength(), 0);
  }

  function testCanBatchCommitOnBehalfOfOthers() public {
    uint64 expiry = uint64(block.timestamp + 10 minutes);

    CommitmentLinkedList.QuoteCommitment[] memory quotes = new CommitmentLinkedList.QuoteCommitment[](5);
    CommitmentLinkedList.Signature[] memory sigs = new CommitmentLinkedList.Signature[](5);
    address[] memory signers = new address[](5);

    // prank from alice to ed
    for (uint16 i = 0; i < 5; i++) {
      uint privKey = i + 1;
      address user = vm.addr(privKey);
      signers[i] = user;

      uint64 nonce = 1;

      uint16 bid = 95 + i;
      uint16 ask = 105 + i;

      quotes[i] = CommitmentLinkedList.QuoteCommitment(subId, bid, ask, expiry, commitmentWeight, nonce);
      bytes32 quoteHash =
        keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quotes[i]))));
      (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, quoteHash); // alice is vm.addr(1)
      sigs[i] = CommitmentLinkedList.Signature(v, r, s);
    }

    commitment.commitBatchOnBehalf(signers, quotes, sigs);

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 5);
  }

  function testCancelQuoteWithNonce() public {
    uint64 expiry = uint64(block.timestamp + 10 minutes);

    // alice sign the order
    vm.startPrank(alice);
    uint64 nonce = 1;
    CommitmentLinkedList.QuoteCommitment memory quote =
      CommitmentLinkedList.QuoteCommitment(subId, 95, 105, expiry, commitmentWeight, nonce);
    bytes32 quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, quoteHash); // alice is vm.addr(1)
    CommitmentLinkedList.Signature memory sig = CommitmentLinkedList.Signature(v, r, s);

    // beofre commit is submitted on-chain, increase the nonce
    commitment.increaseNonce(1);
    vm.stopPrank();

    vm.expectRevert(bytes("nonce"));
    commitment.commitOnBehalf(alice, quote, sig);
  }

  function testEpochsAreUpdatedCorrectly() public {
    assertEq(commitment.collectingEpoch(), 1);
    assertEq(commitment.pendingEpoch(), 0);

    // commit and roll over
    vm.prank(alice);
    commitment.commit(subId, 95, 105, commitmentWeight);
    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // ----- new epoch

    assertEq(commitment.collectingEpoch(), 2);
    assertEq(commitment.pendingEpoch(), 1);

    vm.prank(alice);
    commitment.commit(subId, 95, 105, commitmentWeight);
    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // ----- new epoch

    assertEq(commitment.collectingEpoch(), 3);
    assertEq(commitment.pendingEpoch(), 2);
  }

  function testAutomaticRollover() public {
    // --- epoch 1 ---
    assertEq(commitment.collectingEpoch(), 1);
    assertEq(commitment.pendingEpoch(), 0);

    vm.prank(alice);
    commitment.commit(subId, 95, 105, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);

    // --- epoch 2 ---
    vm.prank(alice);
    // this transaction should automatically rollover epochs
    commitment.commit(subId, 95, 105, commitmentWeight);

    assertEq(commitment.pendingLength(), 1);
    assertEq(commitment.collectingLength(), 1);
    assertEq(commitment.collectingEpoch(), 2);
    assertEq(commitment.pendingEpoch(), 1);

    vm.warp(block.timestamp + 10 minutes);

    // --- epoch 2 ---
    // this transaction should automatically rollover epochs
    commitment.executeCommit(accId, subId, true, 95, commitmentWeight);

    assertEq(commitment.collectingEpoch(), 3);
    assertEq(commitment.pendingEpoch(), 2);
  }

  function testCannotDoubleCommitSameSubId() public {
    vm.startPrank(alice);
    commitment.commit(subId, 95, 105, commitmentWeight);

    vm.expectRevert(CommitmentLinkedList.AlreadyCommitted.selector);
    commitment.commit(subId, 95, 105, commitmentWeight);

    vm.stopPrank();
  }

  function testCommitRecordBindedOrders() public {
    vm.prank(alice);
    commitment.commit(subId, 95, 105, commitmentWeight);

    vm.prank(bob);
    commitment.commit(subId, 95, 105, commitmentWeight);

    vm.prank(charlie);
    commitment.commit(subId, 95, 100, commitmentWeight); // different ask

    vm.warp(block.timestamp + 10 minutes);

    commitment.checkRollover();

    uint64 aliceNodeId = 1;

    (uint16 bidVol, uint16 askVol, uint64 aliceBidIdx, uint64 aliceAskIdx,,) =
      commitment.commitments(commitment.pendingEpoch(), subId, aliceNodeId);
    assertEq(bidVol, 95);
    assertEq(askVol, 105);
    assertEq(aliceBidIdx, 0);
    assertEq(aliceAskIdx, 0);

    uint64 bobNodeId = 2;

    (,, uint64 bobBidIdx, uint64 bobAskIdx,,) = commitment.commitments(commitment.pendingEpoch(), subId, bobNodeId);
    assertEq(bobBidIdx, 1);
    assertEq(bobAskIdx, 1);

    uint64 charlieNodeId = 3;
    (,, uint64 charlieBidIdx, uint64 charlieAskIdx,,) =
      commitment.commitments(commitment.pendingEpoch(), subId, charlieNodeId);
    assertEq(charlieBidIdx, 2);
    assertEq(charlieAskIdx, 0);
  }

  function testCanExecuteCommit() public {
    vm.prank(alice);
    commitment.commit(subId, 96, 107, commitmentWeight); // collecting: 1, pending: 0
    vm.prank(bob);
    commitment.commit(subId, 92, 103, commitmentWeight); // collecting: 2, pending: 0
    vm.prank(charlie);
    commitment.commit(subId, 97, 106, commitmentWeight); // collecting: 3, pending: 0
    vm.prank(david);
    commitment.commit(subId, 91, 100, commitmentWeight); // collecting: 3, pending: 0
    assertEq(commitment.collectingLength(), 4);

    (uint16 lowestBid, uint16 highestBid, uint16 bidLength) = commitment.collectingBidListInfo(subId);
    assertEq(lowestBid, 91);
    assertEq(highestBid, 97);
    assertEq(bidLength, 4);

    (uint16 lowestAsk, uint16 highestAsk, uint16 askLength) = commitment.collectingAskListInfo(subId);
    assertEq(lowestAsk, 100);
    assertEq(highestAsk, 107);
    assertEq(askLength, 4);
  }

  function testCanExecuteCommitMultiple() public {
    vm.prank(alice);
    commitment.commit(subId, 90, 95, commitmentWeight);

    vm.prank(bob);
    commitment.commit(subId, 95, 99, commitmentWeight);

    vm.prank(charlie);
    commitment.commit(subId, 93, 101, commitmentWeight);

    vm.prank(david);
    commitment.commit(subId, 91, 99, commitmentWeight);

    assertEq(commitment.collectingLength(), 4);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    assertEq(commitment.pendingLength(), 4);

    (uint16 lowestBid, uint16 highestBid,) = commitment.pendingBidListInfo(subId);
    assertEq(lowestBid, 90);
    assertEq(highestBid, 95);

    // remove 90 vol
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight); // linked with 95 ask
    commitment.executeCommit(accId, subId, true, 95, commitmentWeight); // linked with 99 ask

    (lowestBid,,) = commitment.pendingBidListInfo(subId);
    assertEq(lowestBid, 91);

    (uint16 lowestAsk, uint16 highestAsk,) = commitment.pendingAskListInfo(subId);
    assertEq(lowestAsk, 99);
    assertEq(highestAsk, 101);

    // // remove ask
    commitment.executeCommit(accId, subId, false, 101, commitmentWeight); // linked with 93 bid

    (lowestAsk, highestAsk,) = commitment.pendingAskListInfo(subId);
    assertEq(lowestAsk, 99);
    assertEq(highestAsk, 99);

    // // bid is also updated
    (lowestBid, highestBid,) = commitment.pendingBidListInfo(subId);
    assertEq(lowestBid, 91);
    assertEq(highestBid, 91);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    (uint16 bestVol, uint64 bidWeight) = commitment.bestFinalizedBids(subId);
    assertEq(bestVol, 91);
    assertEq(bidWeight, commitmentWeight);

    (uint16 bestAsk, uint64 askWeight) = commitment.bestFinalizedAsks(subId);
    assertEq(bestAsk, 99);
    assertEq(askWeight, commitmentWeight);
  }

  function testCannotCommitMoreThanDepositRequirement() public {
    uint128 amount = commitment.getCollatLockUp(commitmentWeight, subId, 80, 100);
    usdc.mint(random, amount);

    vm.startPrank(random);

    usdc.approve(address(commitment), type(uint).max);

    commitment.register();
    commitment.deposit(amount - 1e18);

    vm.expectRevert(stdError.arithmeticError);
    commitment.commit(subId, 80, 100, commitmentWeight);

    vm.stopPrank();
  }

  function testCanExecutePartialSize() public {
    vm.prank(alice);
    commitment.commit(subId, 90, 96, commitmentWeight * 2);

    vm.prank(bob);
    commitment.commit(subId, 92, 98, commitmentWeight * 2);

    vm.prank(charlie);
    commitment.commit(subId, 94, 100, commitmentWeight * 2);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // remove 1 unit
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight);
    // remove another unit
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight);

    (uint lowestBid, uint highestBid,) = commitment.pendingBidListInfo(subId);
    assertEq(lowestBid, 92);
    assertEq(highestBid, 94);

    // (90, 96) order is executed, so asks were also updated
    (uint16 lowestAsk, uint16 highestAsk,) = commitment.pendingAskListInfo(subId);
    assertEq(lowestAsk, 98);
    assertEq(highestAsk, 100);

    // // remove ask, partial weight
    commitment.executeCommit(accId, subId, false, 98, commitmentWeight);
    commitment.executeCommit(accId, subId, false, 100, commitmentWeight);

    (lowestAsk, highestAsk,) = commitment.pendingAskListInfo(subId);
    assertEq(lowestAsk, 98);
    assertEq(highestAsk, 100);
  }

  function testExecuteWillTrade() public {
    vm.prank(alice);
    commitment.commit(subId, 90, 96, commitmentWeight * 2);

    vm.prank(bob);
    commitment.commit(subId, 92, 98, commitmentWeight * 2);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // execute against bids
    commitment.executeCommit(accId, subId, true, 90, commitmentWeight);
    commitment.executeCommit(accId, subId, true, 92, commitmentWeight);

    // check that executing against bids will update executor balance
    assertEq(account.getBalance(accId, optionAsset, subId), -int(uint(2 * commitmentWeight)));

    // execute against asks
    commitment.executeCommit(accId, subId, false, 96, commitmentWeight);
    commitment.executeCommit(accId, subId, false, 98, commitmentWeight);

    // end balace is 0 because sell 2 + buy 2
    assertEq(account.getBalance(accId, optionAsset, subId), 0);
  }

  function testShouldRolloverBlankIfPendingIsEmpty() public {
    //  ----- epoch 1 ------
    vm.prank(alice);
    commitment.commit(subId, 95, 105, commitmentWeight); // collecting: 1, pending: 0
    vm.prank(bob);
    commitment.commit(subId, 96, 106, commitmentWeight); // collecting: 2, pending: 0

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover(); // collecting: 0, pending: 2

    // ----- epoch 1 ------

    vm.prank(alice);
    commitment.commit(subId, 99, 109, commitmentWeight); // collecting: 1, pending: 2
    vm.prank(bob);
    commitment.commit(subId, 95, 110, commitmentWeight); // collecting: 2, pending: 2

    assertEq(commitment.pendingLength(), 2);

    // execute all bids
    commitment.executeCommit(accId, subId, true, 95, commitmentWeight);
    commitment.executeCommit(accId, subId, true, 96, commitmentWeight);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // ----- epoch 2 ------
    (uint16 bestBid, uint64 bidWeights) = commitment.bestFinalizedBids(subId);
    assertEq(bestBid, 0);
    assertEq(bidWeights, 0);

    (uint16 bestAsk, uint64 askWeight) = commitment.bestFinalizedAsks(subId);
    assertEq(bestAsk, 0);
    assertEq(askWeight, 0);

    assertEq(commitment.pendingLength(), 2);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // ----- epoch 3 ------
    (bestBid, bidWeights) = commitment.bestFinalizedBids(subId);
    assertEq(bestBid, 99);
    assertEq(bidWeights, commitmentWeight);

    (bestAsk, askWeight) = commitment.bestFinalizedAsks(subId);
    assertEq(bestAsk, 109);
    assertEq(askWeight, commitmentWeight);

    assertEq(commitment.pendingLength(), 0);

    vm.warp(block.timestamp + 10 minutes);
    commitment.checkRollover();

    // ----- epoch 4 ------
    // Nothing change
    (bestBid, bidWeights) = commitment.bestFinalizedBids(subId);
    assertEq(bestBid, 99);
    assertEq(bidWeights, commitmentWeight);

    (bestAsk, askWeight) = commitment.bestFinalizedAsks(subId);
    assertEq(bestAsk, 109);
    assertEq(askWeight, commitmentWeight);

    assertEq(commitment.pendingLength(), 0);
  }

  function addListings() public {
    uint72[11] memory strikes =
      [500e18, 1000e18, 1300e18, 1400e18, 1450e18, 1500e18, 1550e18, 1600e18, 1700e18, 2000e18, 2500e18];

    uint32[7] memory expiries = [1 weeks, 2 weeks, 4 weeks, 8 weeks, 12 weeks, 26 weeks, 52 weeks];
    for (uint s = 0; s < strikes.length; s++) {
      for (uint e = 0; e < expiries.length; e++) {
        optionAsset.addListing(strikes[s], block.timestamp + expiries[e], true);
      }
    }
  }
}
