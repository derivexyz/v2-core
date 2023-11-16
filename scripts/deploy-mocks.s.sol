// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;


import "forge-std/console2.sol";
import "./types.sol";
import {Utils} from "./utils.sol";

import {MockERC20} from "../test/shared/mocks/MockERC20.sol";


// Deploy mocked contracts: then write to script/input as input for deploying core and v2 markets
contract DeployMocks is Utils {

  /// @dev main function
  function run() external {

    // simple check to make sure no error of overwriting our configs
    if (block.chainid == 1 || block.chainid == 5) revert("Use real USDC on mainnet or goerli");

    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("Start deploying mock contracts! deployer: ", deployer);

    // Deploy Mock USDC
    MockERC20 usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

    MockERC20 wbtc = new MockERC20("WBTC", "WBTC");
    wbtc.setDecimals(8);

    MockERC20 weth = new MockERC20("WETH", "WETH");

    // write to configs file: eg: input/31337/config.json
    string memory objKey = "network-config";
    vm.serializeAddress(objKey, "usdc", address(usdc));
    vm.serializeAddress(objKey, "wbtc", address(wbtc));
    vm.serializeAddress(objKey, "weth", address(weth));
    vm.serializeAddress(objKey, "feedSigner", deployer);
    string memory finalObj = vm.serializeBool(objKey, "useMockedFeed", false);

    // build path
    _writeToInput("config", finalObj);

    vm.stopBroadcast();
  }
}