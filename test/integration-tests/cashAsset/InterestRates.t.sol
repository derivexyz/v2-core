// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

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

    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);

    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);
  }

  function testBorrowAgainstITMCall() public {
    // Alice and Bob deposit cash into the system
    aliceAcc = accounts.createAccount(alice, IManager(pcrm));
    _depositCash(address(alice), aliceAcc, DEFAULT_DEPOSIT);

    bobAcc = accounts.createAccount(bob, IManager(pcrm));
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);

    charlieAcc = accounts.createAccount(charlie, IManager(pcrm));
    _depositCash(address(charlie), charlieAcc, DEFAULT_DEPOSIT);

    console.logInt(accounts.getBalance(aliceAcc, cash, 0));
    console.logInt(accounts.getBalance(bobAcc, cash, 0));
    console.logInt(accounts.getBalance(charlieAcc, cash, 0));

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

    console.log("--- ABOUT TO SUBMIT TRRANSFER HERE ---");
    _managerMintOption(charlieAcc, callId, 1e18);
    console.log("--- AFTER TRRANSFER HERE ---");
    
    assertEq(cash.borrowIndex(), 1e18);
    assertEq(cash.supplyIndex(), 1e18);

    // Borrow against the option
    _withdrawCash(charlie, charlieAcc, DEFAULT_DEPOSIT);

    vm.warp(callExpiry);
    _updatePriceFeed(2100e18, 2,2);
    option.setSettlementPrice(callExpiry);
    (int payout, bool settled) = option.calcSettlementValue(callId, 1e18);
    console2.log("Payout is", payout/1e18);
    console2.log("Settle is", settled);
    // _withdrawCash(charlie, charlieAcc, 1e8);

    // console.logInt(accounts.getBalance(aliceAcc, cash, 0));
    // console.logInt(accounts.getBalance(bobAcc, cash, 0));
    // console.logInt(accounts.getBalance(charlieAcc, cash, 0));


    // console.logInt(accounts.getBalance(aliceAcc, option, callId));
    // console.logInt(accounts.getBalance(charlieAcc, option, callId));
  }
}
