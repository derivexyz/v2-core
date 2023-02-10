// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

// for more info on json parsing:
// https://book.getfoundry.sh/cheatcodes/parse-json#decoding-json-objects-into-solidity-structs
contract JsonMechIO is Test {
  using stdJson for string;

  function loadUints(string memory dirRelativeToRoot, string memory key) public view returns (uint[] memory vals) {
    string memory path = string.concat(vm.projectRoot(), dirRelativeToRoot);
    string memory json = vm.readFile(path);

    // if key value is "pivots", say ".pivots", for more info use:
    // forge uses `jq` syntax for parsing: https://stedolan.github.io/jq/manual/#Basicfilters
    return json.readUintArray(key);
  }
}
