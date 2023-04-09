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
import "./utils.sol";
import "./types.sol";


contract Deploy is Utils {

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

  /// @dev get config from current chainId
  function _getConfig() internal returns (IERC20Metadata usdc, AggregatorV3Interface aggregator) {
    string memory file = readInput("config");
    
    bytes memory usdcAddrRaw = vm.parseJson(file);
    ConfigJson memory config = abi.decode(usdcAddrRaw, (ConfigJson));

    usdc = IERC20Metadata(config.usdc);
    aggregator = AggregatorV3Interface(config.ethAggregator);
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
    // writeToDeployments()
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