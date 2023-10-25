// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import "../../shared/IntegrationTestBase.t.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract INTEGRATION_BorrowAgainstOptionsTest is IntegrationTestBase {
  using DecimalMath for uint;

  address charlie = address(0xca1e);
  uint charlieAcc;

  uint64 expiry;
  IOptionAsset option;

  function setUp() public {
    _setupIntegrationTestComplete();

    option = markets["weth"].option;

    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), markets["weth"].pmrm);

    // Alice and Bob deposit cash into the system
    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT * 2);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT * 2);

    expiry = uint64(block.timestamp + 4 weeks);
    // set forward price for expiry
    _setForwardPrice("weth", expiry, 2000e18, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);
  }

  function testBorrowAgainstITMCall() public {
    // Charlie borrows money against his ITM Call

    uint callStrike = 200e18;
    uint callId = getSubId(expiry, callStrike, true);

    _submitTrade(aliceAcc, option, uint96(callId), 1e18, charlieAcc, cash, 0, 0);

    assertEq(cash.borrowIndex(), 1e18);
    assertEq(cash.supplyIndex(), 1e18);

    // Borrow against the option
    uint borrowAmount = 300e18;
    _withdrawCash(charlie, charlieAcc, borrowAmount);
    // (uint forwardPrice,) = _getForwardPrice("weth", expiry);
    // uint oiFee = markets["weth"].pmrm.OIFeeRateBPS(address(option)).multiplyDecimal(forwardPrice);

    // Charlie balance should be negative
    assertEq(getCashBalance(charlieAcc), -int(borrowAmount));

    vm.warp(block.timestamp + 1 weeks);
    _setSpotPrice("weth", 2000e18, 1e18);

    cash.accrueInterest();
    assertApproxEqAbs(cash.borrowIndex(), 1001344096864415691, 0.001e18);
    assertApproxEqAbs(cash.supplyIndex(), 1000067460170559555, 0.001e18);
  }

  function testBorrowAgainstITMPut() public {
    uint putStrike = 3000e18;
    uint96 putId = getSubId(expiry, putStrike, false);

    _submitTrade(aliceAcc, option, putId, 1e18, charlieAcc, cash, 0, 0);

    assertEq(subAccounts.lastAccountTradeId(charlieAcc), 3);

    assertEq(cash.borrowIndex(), 1e18);
    assertEq(cash.supplyIndex(), 1e18);

    // Borrow against the option
    _withdrawCash(charlie, charlieAcc, 50e18);

    assertEq(subAccounts.lastAccountTradeId(charlieAcc), 4);

    // Charlie balance should be -borrowed amount + oiFee
    // (uint forwardPrice,) = _getForwardPrice("weth", expiry);
    // uint oiFee = markets["weth"].pmrm.OIFeeRateBPS(address(option)).multiplyDecimal(forwardPrice);
    assertEq(subAccounts.getBalance(charlieAcc, cash, 0), -int(50e18));

    vm.warp(block.timestamp + 1 weeks);
    cash.accrueInterest();

    assertEq(subAccounts.lastAccountTradeId(charlieAcc), 4);

    markets["weth"].pmrm.settleInterest(charlieAcc);

    assertEq(subAccounts.lastAccountTradeId(charlieAcc), 5);

    assertApproxEqAbs(cash.borrowIndex(), 1001171311598975475, 0.01e18);
    assertApproxEqAbs(cash.supplyIndex(), 1000006089602394193, 0.01e18);
    //    // interest accural breaks if you run it long enough
    //    for (uint i=0; i<5; i++) {
    //      console2.log(i);
    //      vm.warp(block.timestamp + 100 weeks);
    //      markets["weth"].pmrm.settleInterest(charlieAcc);
    //      srm.settleInterest(aliceAcc);
    //    }
    //
    //    vm.warp(block.timestamp + 100000 weeks);
    //    srm.settleInterest(aliceAcc);
  }
}
