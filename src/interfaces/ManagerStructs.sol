// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./IAsset.sol";

interface ManagerStructs {
  // trade
  struct Trade {
    uint accA;
    uint accB;
    IAsset assetA;
    uint96 assetASubId;
    IAsset assetB;
    uint96 assetBSubId;
    uint128 amountA;
    uint128 amountB;
  }

  // for transfer, look at AccountStructs.AssetTransfer

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

  // Proposals

  struct TransferProposal {
    AccountStructs.AssetTransfer transfer;
    bytes32 senderPreHash;
    uint salt;
  }

  struct TradeProposal {
    Trade trade;
    bytes32 accountAPreHash;
    bytes32 accountBPreHash;
    uint salt;
  }
}
