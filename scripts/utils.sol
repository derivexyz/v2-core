// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";

contract Utils is Script {

  ///@dev read input from json 
  ///@dev standard path: scripts/input/{chainId}/{input}.json, as defined in 
  ////    https://book.getfoundry.sh/tutorials/best-practices?highlight=script#scripts
  function readInput(string memory input) internal view returns (string memory) {
    string memory inputDir = string.concat(vm.projectRoot(), "/scripts/input/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(input, ".json");
    return vm.readFile(string.concat(inputDir, chainDir, file));
  }

  /// @dev this should only be used to deploy mocks for local development
  function writeToInput(string memory filename, string memory content) internal {
    string memory inputDir = string.concat(vm.projectRoot(), "/scripts/input/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(filename, ".json");
    vm.writeJson(content, string.concat(inputDir, chainDir, file));

    console2.log("contented written to ", string.concat(inputDir, chainDir, file));
  }

  /// @dev use this function to write deployed contract address to deployments folder
  function writeToDeployments(string memory filename, string memory content) internal {
    string memory inputDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(filename, ".json");
    vm.writeJson(content, string.concat(inputDir, chainDir, file));

    console2.log("Written to deployment ", string.concat(inputDir, chainDir, file));
  }  
}