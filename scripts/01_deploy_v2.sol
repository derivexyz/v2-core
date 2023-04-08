// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "src/feeds/ChainlinkSpotFeed.sol";
import "src/SecurityModule.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/assets/Option.sol";
import "src/assets/InterestRateModel.sol";
import "src/liquidation/DutchAuction.sol";
import "src/Accounts.sol";
import "src/risk-managers/SpotJumpOracle.sol";

import "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import "forge-std/console2.sol";
import "forge-std/Script.sol";


contract Deploy is Script {

  uint smAcc = 1;

  /// @dev main function
  function run() external {
    vm.startBroadcast();

    console2.log("Start deployment! deployer: ", msg.sender);

    // load configs
    (IERC20Metadata usdc, AggregatorV3Interface aggregator) = _getConfig();
    
    // deploy contracts
    deployAndInitiateContracts(usdc, aggregator);

    vm.stopBroadcast();
  }

  struct ConfigJson { 
    address ethAggregator; 
    address usdc;
  }

  /// @dev get config from current chainId
  function _getConfig() internal returns (IERC20Metadata usdc, AggregatorV3Interface aggregator) {
    string memory file = readInput("config");
    

    bytes memory usdcAddrRaw = vm.parseJson(file);
    ConfigJson memory config = abi.decode(usdcAddrRaw, (ConfigJson));

    usdc = IERC20Metadata(config.usdc);
    aggregator = AggregatorV3Interface(config.ethAggregator);
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

  /// @dev deploy and initiate contracts
  function deployAndInitiateContracts(IERC20Metadata usdc, AggregatorV3Interface aggregator) internal {
    
    Accounts accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    
    ChainlinkSpotFeed feed = new ChainlinkSpotFeed(aggregator, 1 hours);

    (uint minRate, uint rateMultiplier, uint highRateMultiplier, uint optimalUtil) = _getDefaultInterestRateModel();
    InterestRateModel rateModel = new InterestRateModel(minRate, rateMultiplier, highRateMultiplier, optimalUtil);

    CashAsset cash = new CashAsset(accounts, usdc, rateModel, smAcc);

    console2.log("Cash deployed: ", address(cash));

    Option option = new Option(accounts, address(feed));

    console2.log("Option deployed: ", address(option));

    // todo: finish all deployments

    // todo: write to a file similar to how deploy-mocks does it
  }

  function _getDefaultInterestRateModel() internal pure returns (
    uint minRate, 
    uint rateMultiplier, 
    uint highRateMultiplier, 
    uint optimalUtil
  ) {
    minRate = 0.06 * 1e18;
    rateMultiplier = 0.2 * 1e18;
    highRateMultiplier = 0.4 * 1e18;
    optimalUtil = 0.6 * 1e18;
  }
}