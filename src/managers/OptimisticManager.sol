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

contract OptimisticManager is Owned, IManager {
  using DecimalMath for uint;
  using SafeCast for uint;

  IAccount account;

  mapping(uint => bytes32) public lastAccountStateRoot;

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

  ///@dev propose batch transfers
  function proposeTransfersFromProposer(AccountStructs.AssetTransfer[] calldata transfers) external {
    // check msg.sender is proposer

    // store transferDetails

    // add to queue

    // store final states of all relevent accounts
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

  function executeTransersWithVouch(
    uint voucherId,
    Signature memory voucherSignature,
    AccountStructs.AssetTransfer[] calldata transfers
  ) external {
    // validate proposer signature

    // calculate the "max loss" of the trade
    //

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

  /// @dev validate account state with a set of svi curve parameters
  function _validateSVIWithState(AccountStructs.AssetBalance[] memory assetBalances, SVIParameters memory svi)
    internal
    returns (bool valid)
  {
    return true;
  }

  /**
   * ------------------------ *
   *     Manger Interface
   * ------------------------ *
   */

  /// @dev all trades have to go through proposeTransfer
  function handleAdjustment(uint accountId, address, AccountStructs.AssetDelta[] memory, bytes memory) public override {
    revert("bad flow");
  }

  function handleManagerChange(uint, IManager _manager) external view {
    revert("not implemented");
  }
}
