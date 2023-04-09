// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "test/feeds/mocks/MockV3Aggregator.sol";
import "test/shared/mocks/MockERC20.sol";
import "forge-std/console2.sol";

import "./Utils.sol";
import "./types.sol";


contract DeployMocks is Utils {

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
    writeToInput("config", finalObj);

    vm.stopBroadcast();
  }

  
}