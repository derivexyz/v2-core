// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import "test/shared/utils/JsonMechIO.sol";

import "../../shared/PositionBuilderBase.sol";

/**
 * @dev Tests to verify correct fees paid and received by suppliers and borrowers
 */
contract MECH_InterestRateFeesTest is PositionBuilderBase {
  address charlie = address(0xca1e);

  uint charlieAcc;
  JsonMechIO jsonParser;

  function setUp() public {
    _setupIntegrationTestComplete();

    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), markets["weth"].pmrm);

    cash.setSmFee(0.2e18);

    // add more cash into the system
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
  }

  function testNoInterestPaidForNoBorrow() public {
    _depositCash(address(alice), aliceAcc, 1000e18);
    _depositCash(address(bob), bobAcc, DEFAULT_DEPOSIT);
    int alicePreCash = int(getCashBalance(aliceAcc));
    int bobPreCash = int(getCashBalance(bobAcc));
    vm.warp(block.timestamp + 30 days);
    _depositCash(address(alice), aliceAcc, 0);
    _depositCash(address(bob), bobAcc, 0);
    assertEq(alicePreCash, int(getCashBalance(aliceAcc)));
    assertEq(bobPreCash, int(getCashBalance(bobAcc)));
  }

  // todo: test fees paid correct for high util on short time frame (suppliers, borrowers, sm)
  // function testInterestPaidForHighUtil() public {
  //   /// check golden rule pre-trade
  //   uint totalBorrow_creation = cash.totalBorrow();
  //   uint totalSupply_creation = cash.totalSupply();
  //   uint balanceOf_creation = usdc.balanceOf(address(cash));
  //   assertEq(totalSupply_creation - totalBorrow_creation, balanceOf_creation * 1e12);
  //   // open trade
  //   uint64 expiry = uint64(block.timestamp + 4 weeks);
  //   // set vol for this expiry
  //   _setSpotPrice("weth", 2000e18, 1e18);
  //   _setDefaultSVIForExpiry("weth", expiry);
  //   _setForwardPrice("weth", expiry, 2000e18, 1e18);

  //   _openBox("weth", expiry, aliceAcc, bobAcc, 1000e18);

  //   jsonParser = new JsonMechIO();
  //   string memory json =
  //     jsonParser.jsonFromRelPath("/test/integration-tests/assets/cashAsset/json/testInterestPaidForHighUtil.json");

  //   uint stateIdx = 0;
  //   uint maxDelta = 1e12; // 6 decimals accuracy (18 total decimals, allowing the last 6 to be wrong)
  //   assertApproxEqAbs(int(getCashBalance(aliceAcc)), jsonParser.readTableValue(json, "Account0", stateIdx), maxDelta);
  //   assertApproxEqAbs(int(getCashBalance(bobAcc)), jsonParser.readTableValue(json, "Account1", stateIdx), maxDelta);
  //   assertApproxEqAbs(int(getCashBalance(smAcc)), jsonParser.readTableValue(json, "SM", stateIdx), maxDelta);
  //   assertApproxEqAbs(
  //     int(usdc.balanceOf(address(cash)) * 1e12), jsonParser.readTableValue(json, "balanceOf", stateIdx), maxDelta
  //   );
  //   assertApproxEqAbs(int(uint(cash.totalSupply())), jsonParser.readTableValue(json, "totalSupply", stateIdx), maxDelta);
  //   assertApproxEqAbs(int(uint(cash.totalBorrow())), jsonParser.readTableValue(json, "totalBorrow", stateIdx), maxDelta);
  //   assertApproxEqAbs(
  //     int(rateModel.getUtilRate(cash.totalSupply(), cash.totalBorrow())),
  //     jsonParser.readTableValue(json, "Utilization", stateIdx) / 1e2,
  //     maxDelta
  //   );
  //   assertApproxEqAbs(
  //     int(rateModel.getBorrowRate(cash.totalSupply(), cash.totalBorrow())),
  //     jsonParser.readTableValue(json, "borrowRate", stateIdx),
  //     maxDelta
  //   );

  //   // warp and trigger state updates
  //   vm.warp(block.timestamp + 14 days);
  //   stateIdx = 1;

  //   _setSpotPrice("weth", 2000e18, 1e18);
  //   // set vol for this expiry
  //   _setDefaultSVIForExpiry("weth", expiry);
  //   // set forward price for expiry
  //   _setForwardPrice("weth", expiry, 2000e18, 1e18);

  //   // trigger cash updates, deposit $1 to alice to bypass an IM revert due to accrued interest
  //   _depositCash(address(alice), aliceAcc, 10e18);
  //   cash.transferSmFees();
  //   _depositCash(address(bob), bobAcc, 0);
  //   _depositCash(address(securityModule), smAcc, 0);

  //   assertApproxEqAbs(int(getCashBalance(aliceAcc)), jsonParser.readTableValue(json, "Account0", stateIdx), maxDelta);
  //   assertApproxEqAbs(int(getCashBalance(bobAcc)), jsonParser.readTableValue(json, "Account1", stateIdx), maxDelta);
  //   assertApproxEqAbs(int(getCashBalance(smAcc)), jsonParser.readTableValue(json, "SM", stateIdx), maxDelta);
  //   assertApproxEqAbs(
  //     int(usdc.balanceOf(address(cash)) * 1e12), jsonParser.readTableValue(json, "balanceOf", stateIdx), maxDelta
  //   );
  //   assertApproxEqAbs(int(uint(cash.totalSupply())), jsonParser.readTableValue(json, "totalSupply", stateIdx), maxDelta);
  //   assertApproxEqAbs(int(uint(cash.totalBorrow())), jsonParser.readTableValue(json, "totalBorrow", stateIdx), maxDelta);
  //   assertApproxEqAbs(
  //     int(rateModel.getUtilRate(cash.totalSupply(), cash.totalBorrow())),
  //     jsonParser.readTableValue(json, "Utilization", stateIdx) / 1e2,
  //     maxDelta
  //   );
  //   assertApproxEqAbs(
  //     int(rateModel.getBorrowRate(cash.totalSupply(), cash.totalBorrow())),
  //     jsonParser.readTableValue(json, "borrowRate", stateIdx),
  //     maxDelta
  //   );
  // }
}
