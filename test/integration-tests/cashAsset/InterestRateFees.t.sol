// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "test/shared/utils/JsonMechIO.sol";

import "../shared/IntegrationTestBase.sol";

/**
 * @dev Tests to verify correct fees paid and received by suppliers and borrowers
 */
contract MECH_InterestRateFeesTest is IntegrationTestBase {
  address alice = address(0xace);
  address bob = address(0xb0b);
  address charlie = address(0xca1e);
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;
  JsonMechIO jsonParser;

  function setUp() public {
    _setupIntegrationTestComplete();

    vm.prank(alice);
    accounts.setApprovalForAll(address(this), true);

    vm.prank(bob);
    accounts.setApprovalForAll(address(this), true);

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
      console2.log("json", i, sampleInputs[i]);
    }
  }

  // to do single test, in terminal run: `forge test --match-test testNoInterestPaidForNoBorrow -vvvv`
  // todo: test there is no fees when no borrow
  function testNoInterestPaidForNoBorrow() public {}

  // todo: test fees paid correct for low util on short time frame (suppliers, borrowers, sm)
  function testInterestPaidForNormalUtil() public {}

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
