// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";

/**
 * @dev Tests to verify correct fees paid and received by suppliers and borrowers
 */
contract INTEGRATION_InterestRateFeesTest is IntegrationTestBase {
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

    vm.prank(charlie);
    accounts.setApprovalForAll(address(this), true);
  }

  // todo: test there is no fees when no borrow
  function testNoInterestPaidForNoBorrow() public {
  }

  // todo: test fees paid correct for low util on short time frame (suppliers, borrowers, sm) 
  function testInterestPaidForNormalUtil() public {

  }

  // todo: test fees paid correct for low util on long time frame (suppliers, borrowers, sm) 
  function testInterestPaidForNormalUtilLongTerm() public {

  }
  
  // todo: test fees paid correct for high util on short time frame (suppliers, borrowers, sm)
  function testInterestPaidForHighUtil() public {

  }

  // todo: test fees paid correct for high util on long time frame (suppliers, borrowers, sm)
  function testInterestPaidForHighUtil() public {

  }

  // todo: test increase in supply reduces fees 
  function testIncreaseSupplyDecreasesInterest() public {
    
  }

  // todo: test increase in borrow increase fees 
  function testIncreaseBorrowIncreasesInterest() public {

  }
}
