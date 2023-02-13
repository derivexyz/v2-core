// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "forge-std/console.sol";

import "test/shared/utils/JsonMechIO.sol";

import "../shared/IntegrationTestBase.sol";
import "../shared/PositionBuilderBase.sol";

/**
 * @dev Tests to verify correct fees paid and received by suppliers and borrowers
 */
contract MECH_InterestRateFeesTest is PositionBuilderBase {
  address charlie = address(0xca1e);
  
  uint charlieAcc;
  JsonMechIO jsonParser;

  function setUp() public {

    // alice and bob accounts are already setup
    _setupIntegrationTestComplete();

    charlieAcc = accounts.createAccount(charlie, pcrm);

    vm.prank(charlie);
    accounts.setApprovalForAll(address(this), true);

    // example of loading simple Uint array
    // to print the json example, run in terminal: `forge test --match-test testNoInterestPaidForNoBorrow -vvvv`
    jsonParser = new JsonMechIO();
    uint[] memory sampleInputs = jsonParser.loadUints(
      "/test/integration-tests/cashAsset/InterestRateFees.json",
      ".expectedAccruedInterest" // not the "." before the key
    );

    for (uint i; i < sampleInputs.length; i++) {
      //console2.log("json", i, sampleInputs[i]);
    }
  }

  // to do single test, in terminal run: `forge test --match-test testNoInterestPaidForNoBorrow -vvvv`
  // todo: test there is no fees when no borrow
  function testNoInterestPaidForNoBorrow() public {
    _depositCash(address(alice), aliceAcc, 1000e18);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);

    console.log("Start time");
    console.log(block.timestamp);
    console.log("Alice Cash Balance");
    console.logInt(accounts.getBalance(aliceAcc, IAsset(cash), 0) / 1e18);

    console.log("Bob Cash Balance");
    console.logInt(accounts.getBalance(bobAcc, IAsset(cash), 0) / 1e18);

    console.log("End Time");
    console.log(block.timestamp + 2 days);

    _depositCash(address(alice), aliceAcc, 0);
    _depositCash(address(bob), bobAcc, 0);

    console.log("Alice Cash Balance at end");
    console.logInt(accounts.getBalance(aliceAcc, IAsset(cash), 0) / 1e18);

    console.log("Bob Cash Balance at end");
    console.logInt(accounts.getBalance(bobAcc, IAsset(cash), 0) / 1e18);
  }

  // todo: test fees paid correct for low util on short time frame (suppliers, borrowers, sm)
  function testInterestPaidForNormalUtil() public {
    // todo: just showing how PositionBuilderBase works
    // @Sean if you run `forge test --match-contract="(MECH_)" -vv` you'll see
    // that aliceAcc has around -$80 in a leveraged box, and bob has a short box with $100 collat
    aliceAcc = accounts.createAccount(alice, pcrm);
    bobAcc = accounts.createAccount(bob, pcrm);

    console.log("---- POST ACCOUNT CREATION ----");
    console2.log("Alice cash:", getCashBalance(aliceAcc) / 1e18);
    console2.log("Bob cash:", getCashBalance(bobAcc) / 1e18);
    console2.log("SM balance:", getCashBalance(smAcc) / 1e18);
    console2.log("balanceOf(USDC):", usdc.balanceOf(address(cash)));
    console2.log("");

    uint totalBorrow_creation = cash.totalBorrow();
    uint totalSupply_creation = cash.totalSupply();
    uint balanceOf_creation = usdc.balanceOf(address(cash));

    assertEq(totalSupply_creation - totalBorrow_creation, balanceOf_creation);

    // Position[] memory positions = _openATMFwd(aliceAcc, bobAcc);
    Position[] memory positions = _openBox(aliceAcc, bobAcc);
    // Position[] memory positions = _openLeveragedZSC(aliceAcc, bobAcc);
    //console.log("Options:");
    //for (uint i = 0; i < positions.length; i++) {
    // console.logInt(accounts.getBalance(aliceAcc, IAsset(option), positions[i].subId)/1e18);
    //  console.logInt(accounts.getBalance(bobAcc, IAsset(option), positions[i].subId)/1e18);
    //}

    console.log("---- POST TRADE ----");
    console2.log("Alice cash:", getCashBalance(aliceAcc));
    console2.log("Bob cash:", getCashBalance(bobAcc));
    console2.log("SM balance:", getCashBalance(smAcc));
    console2.log("balanceOf(USDC):", usdc.balanceOf(address(cash)));

    uint totalBorrow_postTrade = cash.totalBorrow();
    uint totalSupply_postTrade = cash.totalSupply();
    uint balanceOf_postTrade = usdc.balanceOf(address(cash)) * 1e12;

    console2.log("-----");
    console2.log("Utilization: ", rateModel.getUtilRate(totalSupply_postTrade, totalBorrow_postTrade));
    console2.log("borrowRate: ", rateModel.getBorrowRate(totalSupply_postTrade, totalBorrow_postTrade));

    assertEq(totalSupply_postTrade - totalBorrow_postTrade, balanceOf_postTrade);
    console2.log("");
    vm.warp(block.timestamp + 14 days);

    _setSpotPriceE18(2000e18);

    console.log("---- POST 14 day wait ----");
    _depositCash(address(alice), aliceAcc, 0);
    _depositCash(address(bob), bobAcc, 0);
    _depositCash(address(securityModule), smAcc, 0);

    //securityModule.deposit(100000);
    console2.log("Alice cash:", getCashBalance(aliceAcc));
    console2.log("Bob cash:", getCashBalance(bobAcc));
    console2.log("SM balance:", getCashBalance(smAcc));
    console2.log("balanceOf(USDC):", usdc.balanceOf(address(cash)));
    console2.log("");

    uint totalBorrow_postWait = cash.totalBorrow();
    uint totalSupply_postWait = cash.totalSupply();
    uint balanceOf_postWait = usdc.balanceOf(address(cash)) * 1e12;

    console2.log("-----");
    console2.log("Utilization: ", rateModel.getUtilRate(totalSupply_postWait, totalBorrow_postWait));
    console2.log("borrowRate: ", rateModel.getBorrowRate(totalSupply_postWait, totalBorrow_postWait));

    assertEq(totalSupply_postWait - totalBorrow_postWait, balanceOf_postWait);

    //
  }

  // todo: test fees paid correct for low util on long time frame (suppliers, borrowers, sm)
  function testInterestPaidForNormalUtilLongTerm() public {}

  // todo: test fees paid correct for high util on short time frame (suppliers, borrowers, sm)
  function testInterestPaidForHighUtil() public {}

  // todo: test fees paid correct for high util on long time frame (suppliers, borrowers, sm)
  function testInterestPaidForHighUtilLongTerm() public {}

  // todo: test increase in supply reduces fees
  function testIncreaseSupplyDecreasesInterest() public {}

  // todo: test increase in borrow increase fees
  function testIncreaseBorrowIncreasesInterest() public {}
}
