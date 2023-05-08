// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract INTEGRATION_OIFeeTest is IntegrationTestBase {
  uint constant initCash = 2000e18;

  function setUp() public {
    _setupIntegrationTestComplete();

    // allow this contract to submit trades
    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);
    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);

    // init setup for both accounts
    _depositCash(alice, aliceAcc, initCash);
    _depositCash(bob, bobAcc, initCash);
  }

  function testChargeOIFee() public {
    uint expiry = block.timestamp + 7 days;
    uint spot = _getFuturePrice(expiry);

    uint strike = spot + 1000e18;
    uint96 callToTrade = OptionEncoding.toSubId(expiry, strike, true);
    int amountOfContracts = 10e18;
    int premium = 1750e18;

    // alice send option to bob, bob send premium to alice
    _submitTrade(aliceAcc, option, callToTrade, amountOfContracts, bobAcc, cash, 0, premium);

    uint expectedOIFeeEach = spot * uint(amountOfContracts) / 1e18 / 1000;

    assertEq(getCashBalance(pcrmFeeAcc), int(expectedOIFeeEach) * 2);
    assertEq(getCashBalance(aliceAcc), int(initCash) + premium - int(expectedOIFeeEach));
    assertEq(getCashBalance(bobAcc), int(initCash) - premium - int(expectedOIFeeEach));
  }

  function testClosingChargeNoFee() public {
    // same setup
    uint expiry = block.timestamp + 7 days;
    uint spot = _getFuturePrice(expiry);
    uint strike = spot + 1000e18;
    uint96 callToTrade = OptionEncoding.toSubId(expiry, strike, true);
    int amountOfContracts = 10e18;
    int premium = 1750e18;

    // open positions first
    _submitTrade(aliceAcc, option, callToTrade, amountOfContracts, bobAcc, cash, 0, premium);

    // pre-states before closing trade
    int aliceCashBefore = getCashBalance(aliceAcc);
    int bobCashBefore = getCashBalance(bobAcc);
    int totalFeeBefore = getCashBalance(pcrmFeeAcc);

    // alice pays premium2 to close position short with bob
    int premium2 = 100e18;
    _submitTrade(aliceAcc, cash, 0, premium2, bobAcc, option, callToTrade, amountOfContracts);

    assertEq(getCashBalance(aliceAcc), aliceCashBefore - premium2);
    assertEq(getCashBalance(bobAcc), bobCashBefore + premium2);

    // no more fee
    assertEq(getCashBalance(pcrmFeeAcc), totalFeeBefore);
  }
}
