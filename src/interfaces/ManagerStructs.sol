// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

interface ManagerStructs {
  // svi parameters
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

  // Proposal
  struct TradeProposal {
    AccountStructs.AssetTransfer[] transfers;
    address[] fromSigners;
    bytes32[] senderPreHashes;
    uint salt;
  }

  struct AccountSnapshot {
    uint lastProposalId;
    bytes32 postRoot;
    AccountStructs.AssetBalance[] postBalances;
  }

  struct ProposalInQueue {
    uint[] accounts;
    bytes32[] preTxHashes;
    bytes32[] postTxHashes;
    AccountStructs.AssetTransfer[] transfers;
    uint timestamp;
    bool isChallenged;
  }
}
