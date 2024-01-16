// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

import {Utils} from "./utils.sol";

import {DutchAuction, ISubAccounts, ISecurityModule, ICashAsset} from "../src/liquidation/DutchAuction.sol";
import {SecurityModule} from "../src/SecurityModule.sol";

import "./config-mainnet.sol";


// Deploy mocked contracts: then write to script/input as input for deploying core and v2 markets
contract DeployERC20s is Utils {

  /// @dev main function
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    vm.startBroadcast(deployerPrivateKey);
    address deployer = vm.addr(deployerPrivateKey);

    console2.log("Deployer: ", deployer);
    //////////
    //// PROD
    //////////

    //    DutchAuction auction = new DutchAuction(
    //      ISubAccounts(0xE7603DF191D699d8BD9891b821347dbAb889E5a5),
    //      ISecurityModule(0x8dC92fB0e1C1F1Def6e424E50aaA66dbB124eb54),
    //      ICashAsset(0x57B03E14d409ADC7fAb6CFc44b5886CAD2D5f02b)
    //    );
    //    auction.setAuctionParams(Config.getDefaultAuctionParam());
    //    auction.setSMAccount(1);
    //
    //    auction.setWhitelistManager(0x28c9ddF9A3B29c2E6a561c1BC520954e5A33de5D, true);
    //    auction.setWhitelistManager(0xe7cD9370CdE6C9b5eAbCe8f86d01822d3de205A0, true);
    //    auction.setWhitelistManager(0x45DA02B9cCF384d7DbDD7b2b13e705BADB43Db0D, true);
    //    SM.setWhitelistModule()

    ///////////
    //// STAGING
    ///////////

    // (ISubAccounts _subAccounts, ISecurityModule _securityModule, ICashAsset _cash)
    DutchAuction auction = new DutchAuction(
      ISubAccounts(0xb9ed1cc0c50bca7a391a6819e9cAb466f5501d73),
      ISecurityModule(0x4a22c641649F0582A7BB79D8193CAd25f63f6FCA),
      ICashAsset(0x6caf294DaC985ff653d5aE75b4FF8E0A66025928)
    );
    auction.setAuctionParams(Config.getDefaultAuctionParam());
    auction.setSMAccount(1);

    auction.setWhitelistManager(0x28bE681F7bEa6f465cbcA1D25A2125fe7533391C, true);
    auction.setWhitelistManager(0xDF448056d7bf3f9Ca13d713114e17f1B7470DeBF, true);
    auction.setWhitelistManager(0xbaC0328cd4Af53d52F9266Cdbd5bf46720320A20, true);
    SecurityModule(0x4a22c641649F0582A7BB79D8193CAd25f63f6FCA).setWhitelistModule(address(auction), true);

    console2.log("Auction:", address(auction));
    vm.stopBroadcast();
  }
}
