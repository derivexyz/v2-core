// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";
import "src/libraries/OptionEncoding.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract INTEGRATION_OIFeeTest is IntegrationTestBase {
  address alice = address(0xaa);
  uint aliceAcc;

  address bob = address(0xbb);
  uint bobAcc;

  function setUp() public {
    _setupIntegrationTestComplete();

    aliceAcc = accounts.createAccount(alice, pcrm);
    bobAcc = accounts.createAccount(bob, pcrm);

    // allow this contract to submit trades
    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);
  }

  function testChargeOIFee() public {
    uint initCash = 200e18;
    _depositCash(alice, aliceAcc, initCash);
    _depositCash(bob, bobAcc, initCash);

    uint spot = feed.getSpot(feedId);

    uint expiry = block.timestamp + 7 days;
    uint strike = spot + 1000e18;
    uint96 callToTrade = OptionEncoding.toSubId(expiry, strike, true);
    int amountOfContracts = 10e18;
    int premium = 50e18;

    // alice send option to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callToTrade, amountOfContracts, bobAcc, cash, 0, premium);

    uint expectedOIFeeEach = spot * uint(amountOfContracts) / 1e18 / 1000;

    assertEq(getCashBalance(pcrmFeeAcc), int(expectedOIFeeEach) * 2);
    assertEq(getCashBalance(aliceAcc), int(initCash) + premium - int(expectedOIFeeEach));
    assertEq(getCashBalance(bobAcc), int(initCash) - premium - int(expectedOIFeeEach));
  }
}
