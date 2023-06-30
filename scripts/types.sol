// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SubAccounts} from "../src/SubAccounts.sol";
import {CashAsset} from "../src/assets/CashAsset.sol";
import {InterestRateModel} from "../src/assets/InterestRateModel.sol";
import {SecurityModule} from "../src/SecurityModule.sol";
import {DutchAuction} from "../src/liquidation/DutchAuction.sol";
import {StandardManager} from "../src/risk-managers/StandardManager.sol";
import {SRMPortfolioViewer} from "../src/risk-managers/SRMPortfolioViewer.sol";

import {ISpotFeed} from "../src/interfaces/ISpotFeed.sol";


struct ConfigJson { 
  address usdc;
  address wbtc; // needed if you want to use deploy-market.s.sol with market = wbtc
  address weth; // needed if you want to use deploy-market.s.sol with market = weth
  bool useMockedFeed;
}

struct Deployment {
  SubAccounts subAccounts;
  InterestRateModel rateModel;
  CashAsset cash;
  SecurityModule securityModule;
  DutchAuction auction;
  // standard risk manager: one for the whole system
  StandardManager srm;
  SRMPortfolioViewer srmViewer;

  ISpotFeed stableFeed;
}