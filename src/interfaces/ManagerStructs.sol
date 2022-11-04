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

  // Proposals

  struct TradeProposal {
    Trade trade;
    bytes32 accountAPreHash;
    bytes32 accountBPreHash;
  }

  struct TransferProposal {
    Trade trade;
    bytes32 accountAPreHash;
    bytes32 accountBPreHash;
  }
}
