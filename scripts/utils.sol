// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "./types.sol";

contract Utils is Script {

  function _toLower(string memory str) internal pure returns (string memory) {
    bytes memory bStr = bytes(str);
    bytes memory bLower = new bytes(bStr.length);
    for (uint i = 0; i < bStr.length; i++) {
      // Uppercase character...
      if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
        // So we add 32 to make it lowercase
        bLower[i] = bytes1(uint8(bStr[i]) + 32);
      } else {
        bLower[i] = bStr[i];
      }
    }
    return string(bLower);
  }

  /// @dev get config from current chainId
  function _loadConfig() internal view returns (ConfigJson memory config) {
    string memory file = _readDeploymentFile("shared");

    config.usdc = abi.decode(vm.parseJson(file, ".usdc"), (address));
    config.feedSigners = abi.decode(vm.parseJson(file, ".feedSigners"), (address[]));
    config.useMockedFeed = abi.decode(vm.parseJson(file, ".useMockedFeed"), (bool));
    config.requiredSigners = abi.decode(vm.parseJson(file, ".requiredSigners"), (uint8));
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

  function _loadMarket(string memory marketName) internal view returns (Market memory market) {
    string memory content = _readDeploymentFile(marketName);
    market.option = OptionAsset(vm.parseJsonAddress(content, ".option"));
    market.perp = PerpAsset(vm.parseJsonAddress(content, ".perp"));
    market.base = WrappedERC20Asset(vm.parseJsonAddress(content, ".base"));
    market.spotFeed = LyraSpotFeed(vm.parseJsonAddress(content, ".spotFeed"));
    market.perpFeed = LyraSpotDiffFeed(vm.parseJsonAddress(content, ".perpFeed"));
    market.iapFeed = LyraSpotDiffFeed(vm.parseJsonAddress(content, ".iapFeed"));
    market.ibpFeed = LyraSpotDiffFeed(vm.parseJsonAddress(content, ".ibpFeed"));
    market.volFeed = LyraVolFeed(vm.parseJsonAddress(content, ".volFeed"));
    market.rateFeed = LyraRateFeed(vm.parseJsonAddress(content, ".rateFeed"));
    market.forwardFeed = LyraForwardFeed(vm.parseJsonAddress(content, ".forwardFeed"));
    market.pmrm = PMRM(vm.parseJsonAddress(content, ".pmrm"));
    market.pmrmLib = PMRMLib(vm.parseJsonAddress(content, ".pmrmLib"));
    market.pmrmViewer = BasePortfolioViewer(vm.parseJsonAddress(content, ".pmrmViewer"));
  }

  function _getV2CoreContract(string memory filename, string memory key) internal view returns (address) {
    string memory content = _readDeploymentFile(filename);
    return abi.decode(vm.parseJson(content, string.concat(".", key)), (address));
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

  function _getMarketERC20(string memory name) internal view returns (address) {
    string memory file = _readDeploymentFile("shared");
    return abi.decode(vm.parseJson(file, string.concat(".", _toLower(name))), (address));
  }
}