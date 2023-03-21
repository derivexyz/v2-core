// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "openzeppelin/utils/Strings.sol";

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

  function jsonFromRelPath(string memory dirRelativeToRoot) public returns (string memory json) {
    string memory path = string.concat(vm.projectRoot(), dirRelativeToRoot);
    json = vm.readFile(path);
  }

  // assume the table is in the following format:
  //                   ColNameA       ColNameB  ...   ColNameY  ColNameZ
  // 0            -793886492748  1000000000000  ...          0         4
  // 1            -800422150756  1004507350350  ...          0         4
  // ...................................................................
  // N                     -123            321  ...         49        69
  //
  // User must keep track of the decimals
  //
  // Important:
  // 1) colimns must be sorted alphabetically
  // 2) everything is assumed to be an int
  function readTableValue(string memory json, string memory col, uint index) public pure returns (int val) {
    string memory key = string.concat(".", col);
    key = string.concat(key, "[");
    key = string.concat(key, Strings.toString(index));
    key = string.concat(key, "]");
    return json.readInt(key);
  }
}
