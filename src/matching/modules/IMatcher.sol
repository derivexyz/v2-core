// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMatcher {
  struct VerifiedOrder {
    uint accountId;
    address owner;
    IMatcher matcher;
    bytes data;
    uint nonce;
  }

  function matchOrders(VerifiedOrder[] memory orders, bytes memory matchData) external;
}
