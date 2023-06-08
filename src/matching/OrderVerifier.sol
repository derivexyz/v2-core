// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "src/interfaces/ISubAccounts.sol";
import "./modules/IMatcher.sol";

contract OrderVerifier {
  // (accountID, signer, nonce) must be unique
  struct SignedOrder {
    uint accountId;
    uint nonce;
    IMatcher matcher;
    bytes data;
    uint expiry;
    bytes signature;
    address signer;
  }

  function _verifyOrder(SignedOrder memory order, IMatcher matcher) internal returns (IMatcher.VerifiedOrder memory) {
    // TODO: check signature, nonce, expiry. Make sure no repeated nonce. Limits are handled by the matchers.
    return IMatcher.VerifiedOrder({
      accountId: order.accountId,
      owner: address(0),
      matcher: order.matcher,
      data: order.data,
      nonce: order.nonce
    });
  }
}
