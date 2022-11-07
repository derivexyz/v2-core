// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/cryptography/ECDSA.sol";

import "synthetix/Owned.sol";
import "synthetix/DecimalMath.sol";
import "forge-std/console2.sol";

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";
import "src/interfaces/ManagerStructs.sol";

contract OptimisticManager is Owned, IManager, ManagerStructs, AccountStructs {
  using DecimalMath for uint;
  using SafeCast for uint;

  IAccount account;

  uint public nextProposalId = 1;

  // stores the state after the last submitted and unprocessed trade proposal for each account
  mapping(uint => AccountSnapshot) public lastSnapshot;

  mapping(address => uint) public proposerStakes;

  // Constants
  uint public lyraStakePerProposal = 100 * 1e18;

  constructor(IAccount account_) Owned() {
    account = account_;
  }

  /**
   * ------------------------ *
   *          Errors
   * ------------------------ *
   */
  error OM_BadPreState();

  // need more Lyra to back a proposal
  error OM_NotEnoughStake();

  error OM_BadSignature();

  // revert on bad contract flow
  error OM_NotImplemented();

  /**
   * ------------------------ *
   *       Modifiers
   * ------------------------ *
   */
  modifier onlyVoucher() {
    _;
  }

  /**
   * ------------------------ *
   *    Proposer functions
   * ------------------------ *
   */

  ///@dev stake LYRA and become a proposer
  function stake(uint amount) external {
    // todo: pull LYRA

    proposerStakes[msg.sender] += amount;
  }

  ///@dev propose trades
  ///@param sigs signatures from all relevent party
  function proposeTradesFromProposer(TradeProposal memory proposal, Signature[] calldata sigs) external {
    uint numOfTransfers = proposal.transfers.length;

    // check msg.sender has enough stake
    _lockupLyraStake(msg.sender, numOfTransfers);

    // store transferDetails to queue (so we can execute later)
    uint proposalId = ++nextProposalId;

    // verify signatures from all "from" accounts
    for (uint i; i < numOfTransfers; i++) {
      uint fromAcc = proposal.transfers[i].fromAcc;

      _validateTradeProposalSig(proposal, sigs[i], account.ownerOf(fromAcc));

      if (!_isValidPreState(fromAcc, proposal.senderPreHashes[i])) revert OM_BadPreState();

      // todo: assume no duplicated calls here.
      // possible solution: if &= 0, skip
      _updateAccountSnapshot(fromAcc, proposalId, proposal.transfers);
    }

    // store final states of all relevent accounts to lastProposedStateRoot
  }

  /**
   * ------------------------ *
   *    Voucher Functions
   * ------------------------ *
   */

  ///@dev deposit USDC to become a voucher
  function deposit() external {}

  ///@dev unlock USDC from vouches longer than 5 minutes
  function unlockFunds() external {}

  /**
   * ----------------------------- *
   *  Challenge Pending Proposals
   * ----------------------------- *
   */

  function challengeTradeProposalInQueue(uint accountId, SVIParameters memory svi) external {
    // validate through svi

    // mark as challenged (remove from the queue)

    // burn % of penalty $LYRA

    // give bounty $LYRA to challenger
  }

  /**
   * ------------------------ *
   *     Challenge Vouches
   * ------------------------ *
   */

  function challengeVouch(uint vouchId, SVIParameters memory svi) external {
    // validate through svi

    // mark as challenged (remove from the queue)

    // penalize $USD from the voucher's account

    // reset voucher's deposited value (based on amount penalised)

    // pay the challenger
  }

  /**
   * ------------------------ *
   *      Public Functions
   * ------------------------ *
   */

  ///@dev propose transfers, get signature from proposer
  function proposeTransfersFromUser(
    AssetTransfer[] calldata transfers,
    address proposer,
    Signature memory proposerSignature
  ) external {
    // validate proposer signature

    _lockupLyraStake(proposer, 1);

    // store transferDetails

    // add to queue

    // store final states of all relevent accounts
  }

  function vouchTransfers(uint voucherId, Signature memory voucherSignature, AssetTransfer[] calldata transfers)
    external
  {
    // validate proposer signature

    // calculate the "max loss" of the trade

    // make sure the account has no pending state updates (lastSeenAccountStateRoot)

    // reduce max loss from voucher deposit

    // execute the trade on accounts directly

    // stored the "vouch data" state after transactions, timestamp, deposits
  }

  function executeProposalsInQueue() external {
    // execute on account if not challenged

    // if preState doesn't match the current state, refund the stake to staker and nothing happend. (cancelled)

    // clear lastProposedStateRoots
  }

  /// @dev user execute the commitment from proposer and get some cashback if it's challenged
  function executeProposalCommitment(uint accountId, bytes calldata stateRoot, Signature memory signature) external {}

  /**
   * ------------------------ *
   *        Validations
   * ------------------------ *
   */
  function validateIsValidPreState(uint accountId, bytes32 preStateHash) external returns (bool valid) {
    return _isValidPreState(accountId, preStateHash);
  }

  /// @dev view function to run svi validation on current state of an account
  function validateSVIWithCurrentState(uint accountId, SVIParameters memory svi) external returns (bool valid) {
    AssetBalance[] memory balances = account.getAccountBalances(accountId);
    return _validateSVIWithState(balances, svi);
  }

  /// @dev validate account state with a set of svi curve parameters
  function validateSVIState(AssetBalance[] memory assetBalances, SVIParameters memory svi)
    external
    returns (bool valid)
  {
    return _validateSVIWithState(assetBalances, svi);
  }

  /**
   * ------------------------ *
   *     Manger Interface
   * ------------------------ *
   */

  /// @dev all trades have to go through proposeTransfer
  function handleAdjustment(uint accountId, address, AccountStructs.AssetDelta[] memory, bytes memory) public override {
    // can open up to trades from Account, if voucher signaure is provided in data
    revert OM_NotImplemented();
  }

  function handleManagerChange(uint, IManager _manager) external view {
    revert OM_NotImplemented();
  }

  /**
   * ------------------------------------ *
   *   Internal functions for proposer
   * ------------------------------------ *
   */

  function _lockupLyraStake(address _proposer, uint _numOfTrades) internal {
    uint stake = proposerStakes[_proposer];
    uint cost = lyraStakePerProposal * _numOfTrades;
    if (stake < cost) revert OM_NotEnoughStake();
    unchecked {
      proposerStakes[_proposer] = stake - cost;
    }
  }

  /**
   * ------------------------------------ *
   *   Internal functions for validation
   * ------------------------------------ *
   */

  function _validateTradeProposalSig(TradeProposal memory trade, Signature memory sig, address signer)
    internal
    returns (bool valid)
  {
    bytes32 structHash = keccak256(abi.encode(trade));
    address _signer = ECDSA.recover(structHash, sig.v, sig.r, sig.s);
    if (signer != _signer) revert OM_BadSignature();
  }

  ///@dev validate if provided state hash is valid to execute against. It has to
  ///     1. match the account state from Account.sol
  ///     2. be equivalent to lastSnapshot.postRoot
  function _isValidPreState(uint accountId, bytes32 preStateHash) internal returns (bool valid) {
    bytes32 stored = lastSnapshot[accountId].postRoot;
    if (stored != bytes32(0)) return preStateHash == stored;

    bytes32 currentHash = _getCurrentAccountHash(accountId);
    return preStateHash == currentHash;
  }

  /// @dev update the last proposed root
  function _updateAccountSnapshot(uint accountId, uint proposalId, AssetTransfer[] memory allTransfers) internal {
    // @todo: filter relevent trades
    AssetTransfer[] memory filter = allTransfers;

    (bytes32 postHash, AssetBalance[] memory postBalances) = _previewAccountHash(accountId, allTransfers);

    lastSnapshot[accountId].lastProposalId = proposalId;
    lastSnapshot[accountId].postRoot = postHash;

    // write array to storage. (memory => storage not supported yet)
    for (uint i = 0; i < postBalances.length; i++) {
      lastSnapshot[accountId].postBalances.push(postBalances[i]);
    }
  }

  /// @dev validate account state with a set of svi curve parameters
  function _validateSVIWithState(AssetBalance[] memory assetBalances, SVIParameters memory svi)
    internal
    returns (bool valid)
  {
    return true;
  }

  function _getCurrentAccountHash(uint accountId) internal returns (bytes32) {
    // todo: read from account
    return bytes32(0);
  }

  function _previewAccountHash(uint accountId, AssetTransfer[] memory adjs)
    internal
    returns (bytes32, AssetBalance[] memory)
  {
    // todo: filter out unrelevant transfers

    // todo: if the account is affected by previous proposals, get it from cached storage

    // todo: read from account (preview state after adjustments)
    AssetBalance[] memory balances = new AssetBalance[](0);
    return (keccak256(abi.encode(block.difficulty)), balances);
  }
}
