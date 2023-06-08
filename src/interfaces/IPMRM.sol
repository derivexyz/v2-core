// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {ISpotFeed} from "./ISpotFeed.sol";
import {IForwardFeed} from "./IForwardFeed.sol";
import {IInterestRateFeed} from "./IInterestRateFeed.sol";
import {IVolFeed} from "./IVolFeed.sol";
import {ISettlementFeed} from "./ISettlementFeed.sol";

interface IPMRM {
  enum VolShockDirection {
    None,
    Up,
    Down
  }

  struct Feeds {
    ISpotFeed spotFeed;
    ISpotFeed stableFeed;
    IForwardFeed forwardFeed;
    IInterestRateFeed interestRateFeed;
    IVolFeed volFeed;
    ISettlementFeed settlementFeed;
  }

  struct Portfolio {
    uint spotPrice;
    uint perpPrice;
    uint stablePrice;
    /// cash amount or debt
    int cash;
    /// option holdings per expiry
    ExpiryHoldings[] expiries;
    int perpPosition;
    uint basePosition;
    uint baseValue;
    int totalMtM;
    // Calculated values
    int basisContingency;
    // option + base + perp; excludes fwd/oracle
    uint staticContingency;
    uint confidenceContingency;
    uint minConfidence;
    int perpValue;
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
    VolShockDirection volShock; // i.e. [Up, Down, None]
  }

  ////////////////
  //   Events   //
  ////////////////
  event MaxExpiriesUpdated(uint maxExpiries);
  event MaxAccountSizeUpdated(uint maxAccountSize);
  event InterestRateFeedUpdated(IInterestRateFeed interestRateFeed);
  event VolFeedUpdated(IVolFeed volFeed);
  event SpotFeedUpdated(ISpotFeed spotFeed);
  event StableFeedUpdated(ISpotFeed stableFeed);
  event ForwardFeedUpdated(IForwardFeed forwardFeed);
  event SettlementFeedUpdated(ISettlementFeed settlementFeed);
  event TrustedRiskAssessorUpdated(address riskAssessor, bool trusted);
  event ScenariosUpdated(IPMRM.Scenario[] scenarios);

  ////////////
  // Errors //
  ////////////
  error PMRM_InvalidSpotShock();
  error PMRM_InvalidMaxExpiries();
  error PMRM_InvalidMaxAccountSize();
  error PMRM_UnsupportedAsset();
  error PMRM_InsufficientMargin();
  error PMRM_FindInArrayError();
  error PMRM_OptionExpired();
  error PMRM_TooManyExpiries();
  error PMRM_TooManyAssets();
}
