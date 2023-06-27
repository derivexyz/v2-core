// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SubAccounts} from "../src/SubAccounts.sol";
import {CashAsset} from "../src/assets/CashAsset.sol";
import {InterestRateModel} from "../src/assets/InterestRateModel.sol";
import {SecurityModule} from "../src/SecurityModule.sol";
import {DutchAuction} from "../src/liquidation/DutchAuction.sol";
import {StandardManager} from "../src/risk-managers/StandardManager.sol";

import {ISpotFeed} from "../src/interfaces/ISpotFeed.sol";


struct ConfigJson { 
  address usdc;
  bool useMockedFeed;
}

struct Deployment {
  SubAccounts subAccounts;
  CashAsset cash;
  InterestRateModel rateModel;
  SecurityModule securityModule;
  DutchAuction auction;
  // standard risk manager: one for the whole system
  StandardManager srm;

  ISpotFeed stableFeed;
}