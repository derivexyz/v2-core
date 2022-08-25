pragma solidity ^0.8.13;

import "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "forge-std/console2.sol";

contract Account is ERC721 {
  constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

}
