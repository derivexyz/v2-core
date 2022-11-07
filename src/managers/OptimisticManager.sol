// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "synthetix/DecimalMath.sol";
import "forge-std/console2.sol";

import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccount.sol";
import "src/interfaces/AccountStructs.sol";
import "src/interfaces/ManagerStructs.sol";

contract OptimisticManager is Owned, IManager {
  using DecimalMath for uint;
  using SafeCast for uint;

  IAccount account;

  mapping(uint => bytes32) public lastProposedStateRoot;

  constructor(IAccount account_) Owned() {
    account = account_;
  }

  struct SVIParameters {
    uint a;
    uint b;
    uint c;
    uint d;
    uint e;
  }

  // proposer can give commitment to users that a trade would go through with a signature.
  // if a particular transaction is challenged, user use this commitment to get a "penalty" from proposer
  struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
  }

  /**
   * ------------------------ *
   *          Errors
   * ------------------------ *
   */
  error OM_BadPreState();

  /**
   * ------------------------ *
   *       Modifiers
   * ------------------------ *
   */

  modifier onlyProposer() {
    _;
  }

  modifier onlyVoucher() {
    _;
  }

  /**
   * ------------------------ *
   *    Proposer functions
   * ------------------------ *
   */

  ///@dev stake LYRA and become a proposer
  function stake() external {}

  ///@dev propose transfer
  ///@dev previous state has to be included in signature.
  ///@param sig signature from "fromAcc"
  function proposeTransferFromProposer(ManagerStructs.TransferProposal calldata proposal, Signature memory sig)
    external
  {
    // check msg.sender is proposer

    // verify signatures for "from account"

    // verify the startRoot matches lastProposedStateRoot or the current state of the "from" account
    if (!_isValidPreState(proposal.transfer.fromAcc, proposal.senderPreHash)) revert OM_BadPreState();

    // store transferDetails

    // add to queue

    // store final states of all relevent accounts to lastProposedStateRoot
  }

  ///@dev propose trades
  ///@param sigs signatures from all relevent party
  function proposeTradesFromProposer(AccountStructs.AssetTransfer[] calldata transfers, Signature[] calldata sigs)
    external
  {
    // check msg.sender is proposer

    // verify signatures from both accounts

    // verify the startRoot matches for both accounts
    // for all accounts
    // _isValidPreState()

    // store transferDetails

    // add to queue

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

  function challengeProposalInQueue(uint accountId, SVIParameters memory svi) external {
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
    AccountStructs.AssetTransfer[] calldata transfers,
    uint proposerId,
    Signature memory proposerSignature
  ) external {
    // validate proposer signature

    // store transferDetails

    // add to queue

    // store final states of all relevent accounts
  }

  function vouchTransfers(
    uint voucherId,
    Signature memory voucherSignature,
    AccountStructs.AssetTransfer[] calldata transfers
  ) external {
    // validate proposer signature

    // calculate the "max loss" of the trade

    // make sure the account has no pending state updates (lastSeenAccountStateRoot)

    // reduce max loss from voucher deposit

    // execute the trade on accounts directly

    // stored the "vouch data" state after transactions, timestamp, deposits
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
    AccountStructs.AssetBalance[] memory balances = account.getAccountBalances(accountId);
    return _validateSVIWithState(balances, svi);
  }

  /// @dev validate account state with a set of svi curve parameters
  function validateSVIState(AccountStructs.AssetBalance[] memory assetBalances, SVIParameters memory svi)
    external
    returns (bool valid)
  {
    return _validateSVIWithState(assetBalances, svi);
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
  function _validateSVIWithState(AccountStructs.AssetBalance[] memory assetBalances, SVIParameters memory svi)
    internal
    returns (bool valid)
  {
    return true;
  }

  function _getCurrentAccountHash(uint accountId) internal returns (bytes32) {
    return bytes32(0);
  }

  function _previewAccountHash(uint accountId, AccountStructs.AssetAdjustment[] memory adjs) internal returns (bytes32) {
    return keccak256(abi.encode(block.difficulty));
  }

  /**
   * ------------------------ *
   *     Manger Interface
   * ------------------------ *
   */

  /// @dev all trades have to go through proposeTransfer
  function handleAdjustment(uint accountId, address, AccountStructs.AssetDelta[] memory, bytes memory) public override {
    // can open up to trades from Account, if voucher signaure is provided in data
    revert("bad flow");
  }

  function handleManagerChange(uint, IManager _manager) external view {
    revert("not implemented");
  }
}
