// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "src/interfaces/ISubAccounts.sol";
import "./modules/IMatcher.sol";
import "./AccountsHandler.sol";
import "./OrderVerifier.sol";

contract Matching is AccountsHandler, OrderVerifier {
  address tradeExecutor;

  function verifyAndMatch(SignedOrder[] memory orders, bytes memory matchData) public onlyTradeExecutor {
    IMatcher matcher = orders[0].matcher;
    IMatcher.VerifiedOrder[] memory verifiedOrders = new IMatcher.VerifiedOrder[](orders.length);
    for (uint i = 0; i < orders.length; i++) {
      verifiedOrders[i] = _verifyOrder(orders[i], matcher);
    }
    _submitMatch(matcher, verifiedOrders, matchData);
  }

  function _submitMatch(IMatcher matcher, IMatcher.VerifiedOrder[] memory orders, bytes memory matchData) internal {
    // subaccounts.transfer(matcher, [...orders.accountId]);
    matcher.matchOrders(orders, matchData);
    // Check they came back?
    // Receive back a list of subaccounts and updated owners? This is more general and allows for opening new accounts
    // in matcher modules
  }

  modifier onlyTradeExecutor() {
    require(msg.sender == tradeExecutor, "Only trade executor can call this");
    _;
  }
}
