// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";
import "src/libraries/OptionEncoding.sol";

/**
 * @dev insolvent auction leads to socialize losses
 */
contract INTEGRATION_SocializeLosses is IntegrationTestBase {
  address alice = address(0xaa);
  uint aliceAcc;

  address bob = address(0xbb);
  uint bobAcc;

  // value used for test
  uint aliceCollat = 4000e18;
  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    aliceAcc = accounts.createAccount(alice, pcrm);
    bobAcc = accounts.createAccount(bob, pcrm);

    // allow this contract to submit trades
    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);

    // init setup for both accounts
    _depositCash(alice, aliceAcc, aliceCollat);
    _depositCash(bob, bobAcc, DEFAULT_DEPOSIT);

    expiry = block.timestamp + 7 days;
    callId = OptionEncoding.toSubId(expiry, strike, true);

    // alice will be slightly above init margin ($50)
    _openPosition();
  }

  //
  function testSocializeLosses() public {
    // price went up 200%, now alice is mega insolvent
    _setSpotPriceE18(ETH_PRICE * 2);

    int initMargin = getAccInitMargin(aliceAcc);
    assertEq(initMargin / 1e18, -23820); // -23K underwater

    auction.startAuction(aliceAcc);
  }

  ///@dev alice go short, bob go long
  function _openPosition() public {
    int premium = 200e18;
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }
}
