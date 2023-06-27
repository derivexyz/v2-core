// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "forge-std/console2.sol";
import "./types.sol";
import {Utils} from "./utils.sol";

import {MockERC20} from "../test/shared/mocks/MockERC20.sol";

// get all default params
import "./config.sol";

// Deploy mocked contracts: then write to output file
contract DeployMocks is Utils {

  /// @dev main function
  function run() external {

    // simple check to make sure no error of overwriting our configs
    if (block.chainid == 1 || block.chainid == 5) revert("Use real USDC on mainnet or goerli");

    vm.startBroadcast();

    console2.log("Start deploying mock contracts! deployer: ", msg.sender);

    // Deploy Mock USDC
    MockERC20 usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    // write to configs file: eg: input/31337/config.json
    string memory objKey = "network-config";
    vm.serializeAddress(objKey, "usdc", address(usdc));
    string memory finalObj = vm.serializeBool(objKey, "useMockedFeed", true);

    // build path
    _writeToInput("config", finalObj);

    vm.stopBroadcast();
  }
}