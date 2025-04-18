// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "openzeppelin/access/Ownable.sol";

import {LyraERC20, Ownable} from "../../src/l2/LyraERC20.sol";

contract UNIT_LyraERC20_Test is Test {
  LyraERC20 public usdc;

  function setUp() public {
    usdc = new LyraERC20("USDC", "USDC", 6);
  }

  function testConfigureMinter() public {
    usdc.configureMinter(address(this), true);
    assertTrue(usdc.minters(address(this)));
    usdc.configureMinter(address(this), false);
    assertFalse(usdc.minters(address(this)));
  }

  function testMintAndBurn() public {
    usdc.configureMinter(address(this), true);
    usdc.mint(address(this), 100);
    assertEq(usdc.balanceOf(address(this)), 100);

    usdc.burn(address(this), 50);
    assertEq(usdc.balanceOf(address(this)), 50);
  }

  function testCanOnlyConfigureMinterByOwner() public {
    vm.prank(address(0xaa));
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xaa)));
    usdc.configureMinter(address(this), true);
  }

  function testCanOnlyMintByMinter() public {
    vm.prank(address(0xaa));
    vm.expectRevert(LyraERC20.OnlyMinter.selector);
    usdc.mint(address(this), 100);
  }

  function testDecimals() public {
    assertEq(usdc.decimals(), 6);
  }
}
