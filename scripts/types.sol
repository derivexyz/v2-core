// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubAccounts} from "../src/SubAccounts.sol";
import {CashAsset} from "../src/assets/CashAsset.sol";
import {OptionAsset} from "../src/assets/OptionAsset.sol";
import {PerpAsset} from "../src/assets/PerpAsset.sol";
import {WrappedERC20Asset} from "../src/assets/WrappedERC20Asset.sol";
import {InterestRateModel} from "../src/assets/InterestRateModel.sol";
import {SecurityModule} from "../src/SecurityModule.sol";
import {DutchAuction} from "../src/liquidation/DutchAuction.sol";
import {ISpotFeed} from "../src/interfaces/ISpotFeed.sol";
import {LyraSpotFeed} from "../src/feeds/LyraSpotFeed.sol";
import {LyraSpotDiffFeed} from "../src/feeds/LyraSpotDiffFeed.sol";
import {LyraVolFeed} from "../src/feeds/LyraVolFeed.sol";
import {LyraRateFeedStatic} from "../src/feeds/LyraRateFeedStatic.sol";
import {LyraForwardFeed} from "../src/feeds/LyraForwardFeed.sol";

// Standard Manager (SRM)
import {StandardManager} from "../src/risk-managers/StandardManager.sol";
import {SRMPortfolioViewer} from "../src/risk-managers/SRMPortfolioViewer.sol";

// Portfolio Manager (PMRM)
import {PMRM} from "../src/risk-managers/PMRM.sol";
import {PMRMLib} from "../src/risk-managers/PMRMLib.sol";
import {BasePortfolioViewer} from "../src/risk-managers/BasePortfolioViewer.sol";

// Periphery Contracts
import {OracleDataSubmitter} from "../src/periphery/OracleDataSubmitter.sol";

struct ConfigJson { 
  address usdc;
  address wbtc; // needed if you want to use deploy-market.s.sol with market = wbtc
  address weth; // needed if you want to use deploy-market.s.sol with market = weth
  bool useMockedFeed;
  address feedSigner;
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
  OracleDataSubmitter dataSubmitter;
}

struct Market {
  // lyra asset
  OptionAsset option;
  PerpAsset perp;
  WrappedERC20Asset base;
  // feeds
  LyraSpotFeed spotFeed;
  LyraSpotDiffFeed perpFeed;
  LyraSpotDiffFeed iapFeed;
  LyraSpotDiffFeed ibpFeed;
  LyraVolFeed volFeed;
  LyraRateFeedStatic rateFeed;
  LyraForwardFeed forwardFeed;
  // manager for specific market
  PMRM pmrm;
  PMRMLib pmrmLib;
  BasePortfolioViewer pmrmViewer;
}