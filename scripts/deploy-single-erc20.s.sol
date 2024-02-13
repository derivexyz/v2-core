// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

import {Utils} from "./utils.sol";

import {LyraERC20} from "../src/l2/LyraERC20.sol";


// Deploy contracts manually, must override config file manually to use this
contract DeploySingleERC20 is Utils {

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("Start deploying ERC20 contracts! deployer: ", deployer);

    LyraERC20 snx = new LyraERC20("Lyra SNX", "SNX", 18);

    console2.log("Deployed SNX: ", address(snx));

    vm.stopBroadcast();
  }
}