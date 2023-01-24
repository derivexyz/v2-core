// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/libraries/AbstractOwned.sol";
import "../../src/libraries/Owned.sol";

contract OwnedTest is Test {
  Owned owned;

  function setUp() public {
    owned = new Owned();

    // initially unset
    assertEq(owned.owner(), address(this));
  }

  function testNominateNewOwner() public {
    address to = address(0xaaaa);

    owned.nominateNewOwner(to);
    assertEq(owned.nominatedOwner(), to);

    // can nominate again
    address another = address(0xbbbb);
    owned.nominateNewOwner(another);
    assertEq(owned.nominatedOwner(), another);
  }

  function testCannotNominateFromNonOwner() public {
    address random = address(0xaaaa);

    vm.prank(random);
    vm.expectRevert(AbstractOwned.OnlyOwner.selector);
    owned.nominateNewOwner(random);
  }

  function testAcceptOwnership() public {
    address newOwner = address(0xaaaa);
    owned.nominateNewOwner(newOwner);

    // accept ownershipt
    vm.prank(newOwner);
    owned.acceptOwnership();

    assertEq(owned.owner(), newOwner);
  }

  function testCannotAcceptOwnershipFromNonNominatee() public {
    address newOwner = address(0xaaaa);
    owned.nominateNewOwner(newOwner);

    // accept ownershipt
    address random = address(0xb0b);
    vm.prank(random);
    vm.expectRevert(AbstractOwned.OnlyNominatedOwner.selector);
    owned.acceptOwnership();
  }
}
