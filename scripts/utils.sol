// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "./types.sol";

contract Utils is Script {


  /// @dev get config from current chainId
  function _loadConfig() internal view returns (ConfigJson memory config) {
    string memory file = _readInput("config");

    config.usdc = abi.decode(vm.parseJson(file, ".usdc"), (address));
    config.weth = abi.decode(vm.parseJson(file, ".weth"), (address));
    config.wbtc = abi.decode(vm.parseJson(file, ".wbtc"), (address));
    config.feedSigner = abi.decode(vm.parseJson(file, ".feedSigner"), (address));
    config.useMockedFeed = abi.decode(vm.parseJson(file, ".useMockedFeed"), (bool));
  }

  /// @dev get config from current chainId
  function _loadDeployment() internal view returns (Deployment memory deployment) {
    string memory content = _readDeploymentFile("core");

    deployment.subAccounts = SubAccounts(abi.decode(vm.parseJson(content, ".subAccounts"), (address)));
    deployment.rateModel = InterestRateModel(abi.decode(vm.parseJson(content, ".rateModel"), (address)));
    deployment.cash = CashAsset(abi.decode(vm.parseJson(content, ".cash"), (address)));
    deployment.securityModule = SecurityModule(abi.decode(vm.parseJson(content, ".securityModule"), (address)));
    deployment.auction = DutchAuction(abi.decode(vm.parseJson(content, ".auction"), (address)));
    deployment.srm = StandardManager(abi.decode(vm.parseJson(content, ".srm"), (address)));
    deployment.srmViewer = SRMPortfolioViewer(abi.decode(vm.parseJson(content, ".srmViewer"), (address)));
    deployment.stableFeed = ISpotFeed(abi.decode(vm.parseJson(content, ".stableFeed"), (address)));
  }

  ///@dev read input from json 
  ///@dev standard path: scripts/input/{chainId}/{input}.json, as defined in 
  ////    https://book.getfoundry.sh/tutorials/best-practices?highlight=script#scripts
  function _readInput(string memory input) internal view returns (string memory) {
    string memory inputDir = string.concat(vm.projectRoot(), "/scripts/input/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(input, ".json");
    return vm.readFile(string.concat(inputDir, chainDir, file));
  }

  /// @dev this should only be used to deploy mocks for local development
  function _writeToInput(string memory filename, string memory content) internal {
    string memory inputDir = string.concat(vm.projectRoot(), "/scripts/input/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(filename, ".json");
    vm.writeJson(content, string.concat(inputDir, chainDir, file));

    console2.log("contented written to ", string.concat(inputDir, chainDir, file));
  }

  ///@dev read deployment file from deployments/
  function _readDeploymentFile(string memory fileName) internal view returns (string memory) {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(fileName, ".json");
    return vm.readFile(string.concat(deploymentDir, chainDir, file));
  }

  /// @dev use this function to write deployed contract address to deployments folder
  function _writeToDeployments(string memory filename, string memory content) internal {
    string memory deploymentDir = string.concat(vm.projectRoot(), "/deployments/");
    string memory chainDir = string.concat(vm.toString(block.chainid), "/");
    string memory file = string.concat(filename, ".json");
    vm.writeJson(content, string.concat(deploymentDir, chainDir, file));

    console2.log("Written to deployment ", string.concat(deploymentDir, chainDir, file));
  }

  function _getMarketERC20(string memory name, ConfigJson memory config) internal pure returns (address) {
    if (keccak256(bytes(name)) == keccak256(bytes("weth"))) {
      return config.weth;
    } else if (keccak256(bytes(name)) == keccak256(bytes("wbtc"))) {
      return config.wbtc;
    } else {
      revert("invalid market name");
    }
  }
}