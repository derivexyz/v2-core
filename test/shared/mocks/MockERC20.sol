//SPDX-License-Identifier:ISC
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
  mapping(address => bool) public permitted;

  constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
    permitted[msg.sender] = true;
  }

  function permitMint(address user, bool permit) external {
    require(permitted[msg.sender], "only permitted");
    permitted[user] = permit;
  }

  function mint(address account, uint amount) external {
    require(permitted[msg.sender], "only permitted");
    ERC20._mint(account, amount);
  }

  function burn(address account, uint amount) external {
    require(permitted[msg.sender], "only permitted");
    ERC20._burn(account, amount);
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
