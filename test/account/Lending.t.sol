// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../util/LyraHelper.sol";

contract SocializedLosses is Test, LyraHelper {
  uint public constant SECONDS_PER_YEAR = 31536000;


  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;
  uint davidAcc;
  address orderbook = vm.addr(10);

  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskManager.Scenario[] memory scenarios = new PortfolioRiskManager.Scenario[](1);
    scenarios[0] = PortfolioRiskManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    aliceAcc = createAccountAndDepositDaiLending(alice, 10000000e18);
    bobAcc = createAccountAndDepositDaiLending(bob, 10000000e18);
  }

  function testDeposit() public {
    charlieAcc = createAccountAndDepositDaiLending(charlie, 5000e18);
    // base layer should only reflect pure balance
    assertEq(account.getBalance(charlieAcc, daiLending, 0), 5000e18);

    // asset level fresh balance should also be the same as no borrows
    assertEq(daiLending.getBalance(charlieAcc), 5000e18);
  }

  function testWithdrawal() public {
    daiLending.withdraw(aliceAcc, 10000000e18, charlie);

    // base layer should only reflect pure balance
    assertEq(account.getBalance(aliceAcc, daiLending, 0), 0);

    // asset level fresh balance should also be the same as no borrows
    assertEq(daiLending.getBalance(aliceAcc), 0);

    assertEq(dai.balanceOf(charlie), 10000000e18);
  }

  function testInterestAccrual() public {
    // Alice and Bob both have 20mln DAI lending each
    // We have Charlie deposit 20mln USDC 
    charlieAcc = createAccountAndDepositUSDC(charlie, 20000000e18);

    // set allowances
    setupMaxSingleAssetAllowance(alice, aliceAcc, orderbook, daiLending);
    setupMaxSingleAssetAllowance(bob, bobAcc, orderbook, daiLending);
    setupMaxSingleAssetAllowance(charlie, charlieAcc, orderbook, daiLending);

    // charlie then transfers 10mln DAI to alice: borrowing Dai from system
    vm.startPrank(orderbook);
    AccountStructs.AssetTransfer memory daiLoan = AccountStructs.AssetTransfer({
      fromAcc: charlieAcc,
      toAcc: aliceAcc,
      asset: IAsset(daiLending),
      subId: 0,
      amount: int(10000000e18),
      assetData: bytes32(0)
    });
    account.submitTransfer(daiLoan, "");
    vm.stopPrank();

    // ensure all balances are correct before interests accrue
    assertEq(account.getBalance(aliceAcc, daiLending, 0), 20000000e18);
    assertEq(account.getBalance(bobAcc, daiLending, 0), 10000000e18);
    assertEq(account.getBalance(charlieAcc, daiLending, 0), -10000000e18);
    assertEq(daiLending.getBalance(aliceAcc), 20000000e18);
    assertEq(daiLending.getBalance(bobAcc), 10000000e18);
    assertEq(daiLending.getBalance(charlieAcc), -10000000e18);

    // totals
    assertEq(daiLending.totalBorrow(), 10000000e18);
    assertEq(daiLending.totalSupply(), 30000000e18);

    // warp by a year
    skip(SECONDS_PER_YEAR);

    // accrueInterest(), check balances
    assertApproxEqAbs(daiLending.getBalance(aliceAcc), 20701139e18, 1e18);
    assertApproxEqAbs(daiLending.getBalance(bobAcc), 10350569e18, 1e18);
    assertApproxEqAbs(daiLending.getBalance(charlieAcc), -11051709e18, 1e18);
    assertEq(account.getBalance(aliceAcc, daiLending, 0), 20000000e18);
    assertEq(account.getBalance(bobAcc, daiLending, 0), 10000000e18);
    assertEq(account.getBalance(charlieAcc, daiLending, 0), -10000000e18);

    // check borrow and supply indices
    assertApproxEqAbs(daiLending.totalBorrow(), 11051709e18, 1e18);
    assertApproxEqAbs(daiLending.totalSupply(), 31051709e18, 1e18);
    assertApproxEqAbs(daiLending.borrowIndex(), 110e16, 1e18);
    assertApproxEqAbs(daiLending.supplyIndex(), 103e16, 1e18);

  }

  function testInterestAccrualWithMultipleInteractions() public {}

}
