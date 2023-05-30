// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./ISpotFeed.sol";
import "./IForwardFeed.sol";
import "./IInterestRateFeed.sol";
import "./IVolFeed.sol";
import "./ISettlementFeed.sol";

interface IPMRM {
  enum VolShockDirection {
    None,
    Up,
    Down
  }

  struct Feeds {
    ISpotFeed spotFeed;
    ISpotFeed perpFeed;
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
    int fwdContingency;
    // option + base + perp; excludes fwd/oracle
    uint staticContingency;
    uint confidenceContingency;
    uint minConfidence;
    int perpValue;
  }

  struct ExpiryHoldings {
    uint secToExpiry;
    StrikeHolding[] options;
    // portion unaffected by spot shocks
    uint forwardFixedPortion;
    // portion affected by spot shocks
    uint forwardVariablePortion;
    int64 rate;
    uint minConfidence;
    uint netOptions;
    int mtm;
    int fwdShock1MtM;
    int fwdShock2MtM;
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

  ////////////
  // Errors //
  ////////////
  error PMRM_ExceededBaseOICap();
  error PMRM_UnsupportedAsset();
  error PMRM_InsufficientMargin();
  error PMRM_FindInArrayError();
  error PMRM_OptionExpired();
  error PMRM_TooManyExpiries();
  error PMRM_TooManyAssets();
}
