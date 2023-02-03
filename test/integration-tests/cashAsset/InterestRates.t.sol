// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract INTEGRATION_InterestRatesTest is IntegrationTestBase {
  address alice = address(0xace);
  address bob = address(0xb0b);
  address charlie = address(0xca1e);
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  function setUp() public {
    _setupIntegrationTestComplete();
  }

  function testBorrowAgainstITMCall() public {
    // Alice and Bob deposite cash into the system
    aliceAcc = accounts.createAccount(alice, IManager(pcrm));
    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);

    bobAcc = accounts.createAccount(bob, IManager(pcrm));
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);

    charlieAcc = accounts.createAccount(charlie, IManager(pcrm));
    // _depositCash(address(charlie), charlieAcc, DEFAULT_DEPOSIT);

    // Charlie borrows money against his ITM Call
    uint callExpiry = block.timestamp + 4 weeks;
    uint callStrike = 1200e8;

    uint callId = option.getSubId(callExpiry, callStrike, true);

    AccountStructs.AssetTransfer memory callTransfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: charlieAcc,
      asset: IAsset(option),
      subId: callId,
      amount: 1e18,
      assetData: ""
    });

    accounts.submitTransfer(callTransfer, "");

    assertEq(cash.borrowIndex(), 1e18);
    assertEq(cash.supplyIndex(), 1e18);

    // cash.withdraw(bobAcc, DEFAULT_DEPOSIT * 2, bob);
    _withdrawCash(alice, aliceAcc, DEFAULT_DEPOSIT * 2);

    console.logInt(accounts.getBalance(aliceAcc, cash, 0));
    console.logInt(accounts.getBalance(bobAcc, cash, 0));
    console.logInt(accounts.getBalance(charlieAcc, cash, 0));
  }
}
