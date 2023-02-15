// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "openzeppelin/utils/Strings.sol";
import "forge-std/console2.sol";


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
  // "0"          -793886492748  1000000000000  ...          0         4
  // "1"          -800422150756  1004507350350  ...          0         4
  // ...................................................................
  // "N"                   -123            321  ...         49        69
  // "numDecimals"           10             10  ...         10         0
  // 
  // namely, the original python/pandas table has an integer index that has been converted to string
  // and as its last row, the numer of decimals is included
  // each row except the last one thus stores the test values
  // e.g. value of -793886492748 with numDecimals of 10 means the real number was -79.3886492748
  // and the value of 4 with numDecimals of 0 simply means the int should be treated as is
  // (e.g. it's probably a timestamp)
  // the table above is then assumed to be json'd via:
  // df.to_json("/your-path-to-v2-core/v2-core/test/integration-tests/cashAsset/json/fileName.json")
  // 
  // Important:
  // 1) colimns must be sorted alphabetically
  // 2) "numDecimals" must be the last row
  // 3) the index strings ("0", "1",...) must also be sorted
  // 4) everything is assumed to be an int
  function readTableValue(string memory json, string memory col, uint index) public returns (int val) {
    string memory key = string.concat(".", col);
    key = string.concat(key, ".");
    key = string.concat(key, Strings.toString(index));
    return json.readInt(key);
  }

  // read the "numDecimals" value for the given column
  // allows us to have ints/timestamps in the dataframe mixed together with floats
  // numDecimals can also be different for different cols, e.g. could be 6 for spot / strike, but 10 for utilization
  function readColDecimals(string memory json, string memory col) public returns (uint decimals) {
    string memory key = string.concat(".", col);
    key = string.concat(key, ".numDecimals");
    return json.readUint(key);
  }

  // searches for a value in a column, returning the index
  // useful when there's a column such as "Time", and you want to look-up say spot price recorded at some time
  // searches the column in the order of increasing index
  // returns the first match, and reverts if match was not found
  function findIndexForValue(string memory json, string memory col, int value) public returns (uint index) {
    uint i = 0;
    // int ithValue;
    string memory key;
    while (true) {
      key = string.concat(".", col);
      key = string.concat(key, ".");
      key = string.concat(key, Strings.toString(i));
      try vm.parseJsonInt(json, key) returns (int ithValue) {
        if (ithValue == value) return i;
        else i++;
      } catch {
        revert JsonMechOI_ValueNotFound(col, value);
      }
    }
  }

  error JsonMechOI_ValueNotFound(string, int);
}
