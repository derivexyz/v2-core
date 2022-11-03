// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
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

  ///@dev stake lyra and become a proposer
  function stake() external {}

  ///@dev propose batch transfers
  function proposeTransfersFromProposer(AccountStructs.AssetTransfer[] calldata transfers) external {
    // check msg.sender is proposer

    // make sure the proposer is approved to update account

    // store account state root at the end of transfers
  }

  ///@dev propose batch transfers
  function proposeTransfersFromUser(
    AccountStructs.AssetTransfer[] calldata transfers,
    Signature memory proposerSignature
  ) external {
    // store account state root at the end of transfers
  }

  function challengeState(uint accountId, SVIParameters memory svi) external {}

  /// @dev user execute the commitment from proposer, get the penalty
  function executeCommitment(uint accountId, bytes calldata stateRoot, Signature memory signature) external {}

  /// @dev view function to run svi validation on current account state
  function validateSVIWithCurrentState(uint accountId, SVIParameters memory svi) external returns (bool valid) {
    AccountStructs.AssetBalance[] memory balances = account.getAccountBalances(accountId);
    return _validateSVIWithState(balances, svi);
  }

  function validateSVIState(AccountStructs.AssetBalance[] memory assetBalances, SVIParameters memory svi)
    external
    returns (bool valid)
  {
    return _validateSVIWithState(assetBalances, svi);
  }

  function _validateSVIWithState(AccountStructs.AssetBalance[] memory assetBalances, SVIParameters memory svi)
    internal
    returns (bool valid)
  {
    return true;
  }

  /// @dev all trades have to go through proposeTransfer
  function handleAdjustment(uint accountId, address, AccountStructs.AssetDelta[] memory, bytes memory) public override {
    revert("bad flow");
  }

  function handleManagerChange(uint, IManager _manager) external view {
    revert("not implemented");
  }
}
