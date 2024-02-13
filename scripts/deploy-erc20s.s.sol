// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

import {Utils} from "./utils.sol";

import {LyraERC20} from "../src/l2/LyraERC20.sol";


// Deploy mocked contracts: then write to script/input as input for deploying core and v2 markets
contract DeployERC20s is Utils {

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("Start deploying ERC20 contracts! deployer: ", deployer);

    LyraERC20 usdc = new LyraERC20("USDC", "USDC", 6);
    LyraERC20 usdt = new LyraERC20("Lyra USDT", "USDT", 6);
    LyraERC20 wbtc = new LyraERC20("Lyra WBTC", "WBTC", 8);
    LyraERC20 weth = new LyraERC20("Lyra WETH", "WETH", 18);
    LyraERC20 snx = new LyraERC20("Lyra SNX", "SNX", 18);

    address[] memory feedSigners = new address[](1);
    feedSigners[0] = deployer;

    // write to configs file: eg: input/31337/config.json
    string memory objKey = "network-config";
    vm.serializeAddress(objKey, "usdc", address(usdc));
    vm.serializeAddress(objKey, "btc", address(wbtc));
    vm.serializeAddress(objKey, "eth", address(weth));
    vm.serializeAddress(objKey, "usdt", address(usdt));
    vm.serializeAddress(objKey, "snx", address(snx));
    vm.serializeAddress(objKey, "feedSigners", feedSigners);
    string memory finalObj = vm.serializeBool(objKey, "useMockedFeed", false);

    // build path
    _writeToInput("config", finalObj);

    vm.stopBroadcast();
  }
}