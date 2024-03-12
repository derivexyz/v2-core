// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/ERC20.sol";
import "openzeppelin/access/AccessControl.sol";

contract StrandsAPI is ERC20, AccessControl {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  constructor(address defaultAdmin, address minter) ERC20("Strands API", "Strands.api") {
    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _grantRole(MINTER_ROLE, minter);
  }

  function mint(address to, uint amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  function burn(uint amount) public onlyRole(MINTER_ROLE) {
    _burn(_msgSender(), amount);
  }
}
