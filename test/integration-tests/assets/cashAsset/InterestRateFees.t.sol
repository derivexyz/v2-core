// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
//
//import "forge-std/Test.sol";
//import "forge-std/console2.sol";
//
//import "test/shared/utils/JsonMechIO.sol";
//
//import "../../shared/IntegrationTestBase.sol";
//import "../../shared/PositionBuilderBase.sol";
//
///**
// * @dev Tests to verify correct fees paid and received by suppliers and borrowers
// */
//contract MECH_InterestRateFeesTest is PositionBuilderBase {
//  address charlie = address(0xca1e);
//
//  uint charlieAcc;
//  JsonMechIO jsonParser;
//
//  function setUp() public {
//    // alice and bob accounts are already setup
//    _setupIntegrationTestComplete();
//
//    charlieAcc =subAccounts.createAccount(charlie, pcrm);
//
//    vm.prank(charlie);
//   subAccounts.setApprovalForAll(address(this), true);
//
//    // todo: move the SM fee to the IntegrationTestBase?
//    cash.setSmFee(0.2e18);
//    pcrm.setFeeRecipient(smAcc);
//  }
//
//  // to do single test, in terminal run: `forge test --match-test testNoInterestPaidForNoBorrow -vvvv`
//  // todo: test there is no fees when no borrow
//  function testNoInterestPaidForNoBorrow() public {
//    _depositCash(address(alice), aliceAcc, 1000e18);
//    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
//    int alicePreCash = int(getCashBalance(aliceAcc));
//    int bobPreCash = int(getCashBalance(bobAcc));
//    vm.warp(block.timestamp + 30 days);
//    _depositCash(address(alice), aliceAcc, 0);
//    _depositCash(address(bob), bobAcc, 0);
//    assertEq(alicePreCash, int(getCashBalance(aliceAcc)));
//    assertEq(bobPreCash, int(getCashBalance(bobAcc)));
//  }
//
//  // todo: test fees paid correct for low util on short time frame (suppliers, borrowers, sm)
//  function testInterestPaidForNormalUtil() public {}
//
//  // todo: test fees paid correct for low util on long time frame (suppliers, borrowers, sm)
//  function testInterestPaidForNormalUtilLongTerm() public {}
//
//  // todo: test fees paid correct for high util on short time frame (suppliers, borrowers, sm)
//  // function testInterestPaidForHighUtil() public {
//  //   aliceAcc =subAccounts.createAccount(alice, pcrm);
//  //   bobAcc =subAccounts.createAccount(bob, pcrm);
//  //   /// check golden rule pre-trade
//  //   uint totalBorrow_creation = cash.totalBorrow();
//  //   uint totalSupply_creation = cash.totalSupply();
//  //   uint balanceOf_creation = usdc.balanceOf(address(cash));
//  //   assertEq(totalSupply_creation - totalBorrow_creation, balanceOf_creation);
//  //   // open trade
//  //   _openBox(aliceAcc, bobAcc, 1000e18);
//
//  //   jsonParser = new JsonMechIO();
//  //   string memory json =
//  //     jsonParser.jsonFromRelPath("/test/integration-tests/assets/cashAsset/json/testInterestPaidForHighUtil.json");
//
//  //   uint stateIdx = 0;
//  //   uint maxDelta = 1e12; // 6 decimals accuracy (18 total decimals, allowing the last 6 to be wrong)
//  //   assertApproxEqAbs(int(getCashBalance(aliceAcc)), jsonParser.readTableValue(json, "Account0", stateIdx), maxDelta);
//  //   assertApproxEqAbs(int(getCashBalance(bobAcc)), jsonParser.readTableValue(json, "Account1", stateIdx), maxDelta);
//  //   assertApproxEqAbs(int(getCashBalance(smAcc)), jsonParser.readTableValue(json, "SM", stateIdx), maxDelta);
//  //   assertApproxEqAbs(
//  //     int(usdc.balanceOf(address(cash)) * 1e12), jsonParser.readTableValue(json, "balanceOf", stateIdx), maxDelta
//  //   );
//  //   assertApproxEqAbs(int(uint(cash.totalSupply())), jsonParser.readTableValue(json, "totalSupply", stateIdx), maxDelta);
//  //   assertApproxEqAbs(int(uint(cash.totalBorrow())), jsonParser.readTableValue(json, "totalBorrow", stateIdx), maxDelta);
//  //   assertApproxEqAbs(
//  //     int(rateModel.getUtilRate(cash.totalSupply(), cash.totalBorrow())),
//  //     jsonParser.readTableValue(json, "Utilization", stateIdx) / 1e2,
//  //     maxDelta
//  //   );
//  //   assertApproxEqAbs(
//  //     int(rateModel.getBorrowRate(cash.totalSupply(), cash.totalBorrow())),
//  //     jsonParser.readTableValue(json, "borrowRate", stateIdx),
//  //     maxDelta
//  //   );
//
//  //   // warp and trigger state updates
//  //   vm.warp(block.timestamp + 14 days);
//  //   stateIdx = 1;
//  //   _setSpotPriceE18(2000e18);
//  //   // trigger cash updates, deposit $1 to alice to bypass an IM revert due to accrued interest
//  //   _depositCash(address(alice), aliceAcc, 10e18);
//  //   cash.transferSmFees();
//  //   _depositCash(address(bob), bobAcc, 0);
//  //   _depositCash(address(securityModule), smAcc, 0);
//
//  //   assertApproxEqAbs(int(getCashBalance(aliceAcc)), jsonParser.readTableValue(json, "Account0", stateIdx), maxDelta);
//  //   assertApproxEqAbs(int(getCashBalance(bobAcc)), jsonParser.readTableValue(json, "Account1", stateIdx), maxDelta);
//  //   assertApproxEqAbs(int(getCashBalance(smAcc)), jsonParser.readTableValue(json, "SM", stateIdx), maxDelta);
//  //   assertApproxEqAbs(
//  //     int(usdc.balanceOf(address(cash)) * 1e12), jsonParser.readTableValue(json, "balanceOf", stateIdx), maxDelta
//  //   );
//  //   assertApproxEqAbs(int(uint(cash.totalSupply())), jsonParser.readTableValue(json, "totalSupply", stateIdx), maxDelta);
//  //   assertApproxEqAbs(int(uint(cash.totalBorrow())), jsonParser.readTableValue(json, "totalBorrow", stateIdx), maxDelta);
//  //   assertApproxEqAbs(
//  //     int(rateModel.getUtilRate(cash.totalSupply(), cash.totalBorrow())),
//  //     jsonParser.readTableValue(json, "Utilization", stateIdx) / 1e2,
//  //     maxDelta
//  //   );
//  //   assertApproxEqAbs(
//  //     int(rateModel.getBorrowRate(cash.totalSupply(), cash.totalBorrow())),
//  //     jsonParser.readTableValue(json, "borrowRate", stateIdx),
//  //     maxDelta
//  //   );
//  // }
//
//  // todo: test fees paid correct for high util on long time frame (suppliers, borrowers, sm)
//  function testInterestPaidForHighUtilLongTerm() public {}
//
//  // todo: test increase in supply reduces fees
//  function testIncreaseSupplyDecreasesInterest() public {}
//
//  // todo: test increase in borrow increase fees
//  function testIncreaseBorrowIncreasesInterest() public {}
//}
