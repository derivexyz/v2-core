// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {ISpotFeed} from "./ISpotFeed.sol";
import {IForwardFeed} from "./IForwardFeed.sol";
import {IInterestRateFeed} from "./IInterestRateFeed.sol";
import {IVolFeed} from "./IVolFeed.sol";

interface IPMRM_2_1 {
  enum VolShockDirection {
    None,
    Up,
    Down,
    Linear,
    Abs
  }

  struct Feeds {
    ISpotFeed spotFeed;
    ISpotFeed stableFeed;
    IForwardFeed forwardFeed;
    IInterestRateFeed interestRateFeed;
    IVolFeed volFeed;
  }

  struct Portfolio {
    uint spotPrice;
    uint perpPrice;
    uint stablePrice;
    /// cash amount or debt
    int cash;
    /// option holdings per expiry
    ExpiryHoldings[] expiries;
    CollateralHoldings[] collaterals;
    int perpPosition;
    int totalMtM;
    // Calculated values
    int basisContingency;
    // option + base + perp; excludes fwd/oracle
    uint MMDiscount;
    uint IMDiscount;
    uint minConfidence;
    int perpValue;
  }

  struct CollateralHoldings {
    address asset;
    uint value;
    uint minConfidence;
  }

  struct ExpiryHoldings {
    // used as key
    uint expiry;
    uint secToExpiry;
    StrikeHolding[] options;
    // portion unaffected by spot shocks
    uint forwardFixedPortion;
    // portion affected by spot shocks
    uint forwardVariablePortion;
    // We always assume the rate is >= 0
    uint rate;
    uint minConfidence;
    uint netOptions;
    int mtm;
    int basisScenarioUpMtM;
    int basisScenarioDownMtM;
    uint volShockUp;
    uint volShockDown;
    uint staticDiscount;
  }

  struct StrikeHolding {
    /// strike price of held options
    uint strike;
    uint vol;
    int amount;
    bool isCall;
    bool seenInFilter;
  }

  struct PortfolioExpiryData {
    uint64 expiry;
    uint optionCount;
  }

  struct Scenario {
    uint spotShock; // i.e. 1.2e18 = 20% spot shock up
    VolShockDirection volShock; // i.e. [None, Up, Down, Linear, Abs]
    // Multiply the result by this percentage 0-1, where 1 is no dampening.
    uint dampeningFactor;
  }

  ////////////////
  //   Events   //
  ////////////////
  event MaxExpiriesUpdated(uint maxExpiries);
  event InterestRateFeedUpdated(IInterestRateFeed interestRateFeed);
  event VolFeedUpdated(IVolFeed volFeed);
  event SpotFeedUpdated(ISpotFeed spotFeed);
  event StableFeedUpdated(ISpotFeed stableFeed);
  event ForwardFeedUpdated(IForwardFeed forwardFeed);
  event ScenariosUpdated(Scenario[] scenarios);

  ////////////
  // Errors //
  ////////////
  error PMRM_InvalidSpotShock();
  error PMRM_UnsupportedAsset();
  error PMRM_InsufficientMargin();
  error PMRM_InvalidScenarios();
  error PMRM_InvalidMaxExpiries();
  error PMRM_FindInArrayError();
  error PMRM_OptionExpired();
  error PMRM_TooManyExpiries();
  error PMRM_TooManyAssets();
}
