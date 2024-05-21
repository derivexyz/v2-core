// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/console2.sol";
import {Utils} from "./utils.sol";

import "../test/feed/integration-tests/sfp-contracts/StrandsAPI.sol";
import "../test/feed/integration-tests/sfp-contracts/StrandsSFP.sol";


  struct SFPDeployment {
    address strandsAPI;
    address strandsSFP;
  }


contract DeployBaseAsset is Utils {
  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

    vm.startBroadcast(deployerPrivateKey);

    address deployer = vm.addr(deployerPrivateKey);
    console2.log("deployer: ", deployer);

    string memory file = _readDeploymentFile("core");
    address subAccounts = abi.decode(vm.parseJson(file, ".subAccounts"), (address));

    StrandsAPI strandsAPI = new StrandsAPI(deployer, deployer);
    console2.log("StrandsAPI: ", address(strandsAPI));

    StrandsSFP strandsSFP = new StrandsSFP(strandsAPI);
    console2.log("StrandsSFP: ", address(strandsSFP));

    _writeStrandsDeployment(SFPDeployment({
      strandsAPI: address(strandsAPI),
      strandsSFP: address(strandsSFP)
    }));
  }

  function _writeStrandsDeployment(SFPDeployment memory sfpDeployment) internal {
    string memory objKey = "sfp-deployment";

    vm.serializeAddress(objKey, "api", sfpDeployment.strandsAPI);
    string memory finalObj = vm.serializeAddress(objKey, "sfp", sfpDeployment.strandsSFP);

    _writeToDeployments("strands", finalObj);
  }
}