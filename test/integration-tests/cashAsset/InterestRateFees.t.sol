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
    string memory json = jsonParser.jsonFromRelPath(
      "/test/integration-tests/cashAsset/json/testInterestPaidForHighUtil.json"
      );
    // console2.log("parsing json...");
    // console2.log(jsonParser.readTableValue(json, "Account1", 1));
    // console2.log(jsonParser.readTableValue(json, "Account0", 0));
    // console2.log(jsonParser.readTableValue(json, "borrowRate", 0));

    // console2.log(jsonParser.readColDecimals(json, "Spot"));
    // console2.log(jsonParser.readColDecimals(json, "txType"));

    // uint i = jsonParser.findIndexForValue(json, "Time", 1209601);
    // console2.log(jsonParser.readTableValue(json, "SM", i));

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
  function testInterestPaidForHighUtil() public {
    aliceAcc = accounts.createAccount(alice, pcrm);
    bobAcc = accounts.createAccount(bob, pcrm);
    /// check golden rule pre-trade
    uint totalBorrow_creation = cash.totalBorrow();
    uint totalSupply_creation = cash.totalSupply();
    uint balanceOf_creation = usdc.balanceOf(address(cash));
    assertEq(totalSupply_creation - totalBorrow_creation, balanceOf_creation);
    // open trade
    Position[] memory positions = _openBox(aliceAcc, bobAcc);

    jsonParser = new JsonMechIO();
    string memory json = jsonParser.jsonFromRelPath(
      "/test/integration-tests/cashAsset/json/testInterestPaidForHighUtil.json"
    );

    uint stateIdx = 0;
    uint maxDelta = 1e12; // 6 decimals accuracy (18 total decimals, allowing the last 6 to be wrong)
    assertApproxEqAbs(int(getCashBalance(aliceAcc)), jsonParser.readTableValue(json, "Account0", stateIdx), maxDelta);
    assertApproxEqAbs(int(getCashBalance(bobAcc)), jsonParser.readTableValue(json, "Account1", stateIdx), maxDelta);
    assertApproxEqAbs(int(getCashBalance(smAcc)), jsonParser.readTableValue(json, "SM", stateIdx), maxDelta);
    assertApproxEqAbs(int(usdc.balanceOf(address(cash))*1e12), jsonParser.readTableValue(json, "balanceOf", stateIdx), maxDelta);
    assertApproxEqAbs(int(cash.totalSupply()), jsonParser.readTableValue(json, "totalSupply", stateIdx), maxDelta);
    assertApproxEqAbs(int(cash.totalBorrow()), jsonParser.readTableValue(json, "totalBorrow", stateIdx), maxDelta);
    assertApproxEqAbs(int(rateModel.getUtilRate(cash.totalSupply(), cash.totalBorrow())),
     jsonParser.readTableValue(json, "Utilization", stateIdx) / 1e2, maxDelta);
    assertApproxEqAbs(int(rateModel.getBorrowRate(cash.totalSupply(), cash.totalBorrow())), 
     jsonParser.readTableValue(json, "borrowRate", stateIdx), maxDelta);

    // warp and trigger state updates
    vm.warp(block.timestamp + 14 days);
    stateIdx = 1;
    _setSpotPriceE18(2000e18);
    // trigger cash updates
    _depositCash(address(alice), aliceAcc, 0);
    _depositCash(address(bob), bobAcc, 0);
    _depositCash(address(securityModule), smAcc, 0);

    assertApproxEqAbs(int(getCashBalance(aliceAcc)), jsonParser.readTableValue(json, "Account0", stateIdx), maxDelta);
    assertApproxEqAbs(int(getCashBalance(bobAcc)), jsonParser.readTableValue(json, "Account1", stateIdx), maxDelta);
    assertApproxEqAbs(int(getCashBalance(smAcc)), jsonParser.readTableValue(json, "SM", stateIdx), maxDelta);
    assertApproxEqAbs(int(usdc.balanceOf(address(cash))*1e12), jsonParser.readTableValue(json, "balanceOf", stateIdx), maxDelta);
    assertApproxEqAbs(int(cash.totalSupply()), jsonParser.readTableValue(json, "totalSupply", stateIdx), maxDelta);
    assertApproxEqAbs(int(cash.totalBorrow()), jsonParser.readTableValue(json, "totalBorrow", stateIdx), maxDelta);
    assertApproxEqAbs(int(rateModel.getUtilRate(cash.totalSupply(), cash.totalBorrow())),
     jsonParser.readTableValue(json, "Utilization", stateIdx) / 1e2, maxDelta);
    assertApproxEqAbs(int(rateModel.getBorrowRate(cash.totalSupply(), cash.totalBorrow())), 
     jsonParser.readTableValue(json, "borrowRate", stateIdx), maxDelta);
  }

  // todo: test fees paid correct for high util on long time frame (suppliers, borrowers, sm)
  function testInterestPaidForHighUtilLongTerm() public {}

  // todo: test increase in supply reduces fees
  function testIncreaseSupplyDecreasesInterest() public {}

  // todo: test increase in borrow increase fees
  function testIncreaseBorrowIncreasesInterest() public {}
}
