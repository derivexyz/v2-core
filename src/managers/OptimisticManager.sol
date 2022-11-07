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

  mapping(uint => bytes32) public lastProposedStateRoot;

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

  ///@dev propose transfer
  ///@dev previous state has to be included in signature.
  ///@param sig signature from "fromAcc"
  function proposeTransferFromProposer(TransferProposal calldata proposal, Signature memory sig) external {
    // check msg.sender has enough stake
    _lockupLyraStake(msg.sender, 1);

    _validateTransferProposalSig(proposal, sig, account.ownerOf(proposal.transfer.fromAcc));

    // verify the startRoot matches lastProposedStateRoot or the current state of the "from" account
    if (!_isValidPreState(proposal.transfer.fromAcc, proposal.senderPreHash)) revert OM_BadPreState();

    // store transferDetails to queue (so we can execute later)

    // store final states of all relevent accounts to lastProposedStateRoot
  }

  ///@dev propose trades
  ///@param sigs signatures from all relevent party
  function proposeTradesFromProposer(AssetTransfer[] calldata transfers, Signature[] calldata sigs) external {
    // check msg.sender has enough stake
    _lockupLyraStake(msg.sender, 2);

    // verify signatures from both accounts

    // verify the startRoot matches for both accounts
    // for all accounts
    // _isValidPreState()

    // store transferDetails to queue (so we can execute later)

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
   * ------------------------ *
   * Challenge Pending Trades
   * ------------------------ *
   */

  function challengeTransferProposalInQueue(uint accountId, SVIParameters memory svi) external {
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

  function _validateTransferProposalSig(TransferProposal memory transfer, Signature memory sig, address signer)
    internal
    returns (bool valid)
  {
    bytes32 structHash = keccak256(abi.encode(transfer));
    address _signer = ECDSA.recover(structHash, sig.v, sig.r, sig.s);
    if (signer != _signer) revert OM_BadSignature();
  }

  ///@dev validate if provided state hash is valid to execute against. It has to
  ///     1. match the account state from Account.sol
  ///     2. be equivalent to lastProposedStateRoot
  function _isValidPreState(uint accountId, bytes32 preStateHash) internal returns (bool valid) {
    bytes32 stored = lastProposedStateRoot[accountId];
    if (stored != bytes32(0)) return preStateHash == stored;

    bytes32 currentHash = _getCurrentAccountHash(accountId);
    return preStateHash == currentHash;
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

  function _previewAccountHash(uint accountId, AssetAdjustment[] memory adjs) internal returns (bytes32) {
    // todo: read from account (preview state after adjustments)
    return keccak256(abi.encode(block.difficulty));
  }
}
