// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "test/feeds/mocks/MockV3Aggregator.sol";
import "test/shared/mocks/MockERC20.sol";

import "forge-std/console2.sol";
import "forge-std/Script.sol";

struct ConfigJson { 
  address ethAggregator; 
  address usdc;
}

contract Deploy is Script {

  uint smAcc = 1;

  /// @dev main function
  function run() external {
    vm.startBroadcast();

    console2.log("Start deploying mocked USDC & aggregator! deployer: ", msg.sender);

    // deploy contracts
    MockERC20 usdc = new MockERC20("USDC", "USDC");
    MockV3Aggregator aggregator = new MockV3Aggregator(8, 2000e18);

    console2.log("usdc", address(usdc));
    console2.log("aggregator", address(aggregator));
    
    // store to local file input/31337/config.json
    string memory objKey = "some key";
    vm.serializeAddress(objKey, "ethAggregator", address(aggregator));
    string memory finalObj = vm.serializeAddress(objKey, "usdc", address(usdc));

    // build path
    string memory inputDir = string.concat(vm.projectRoot(), "/scripts/input/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat("config.json");
    vm.writeJson(finalObj, string.concat(inputDir, chainDir, file));

    console2.log("local mocked addresses stored at ", string.concat(inputDir, chainDir, file));

    vm.stopBroadcast();
  }

  ///@dev read input from json 
  ///@dev standard path: scripts/input/{chainId}/{input}.json, as defined in 
  ////    https://book.getfoundry.sh/tutorials/best-practices?highlight=script#scripts
  function readInput(string memory input) internal view returns (string memory) {
    string memory inputDir = string.concat(vm.projectRoot(), "/scripts/input/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(input, ".json");
    return vm.readFile(string.concat(inputDir, chainDir, file));
  }

  
}