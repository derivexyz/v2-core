interface IPMRM {
  enum VolShockDirection {
    None,
    Up,
    Down
  }

  struct PMRM_Portfolio {
    uint spotPrice;
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
    int unrealisedPerpValue;
  }

  struct ExpiryHoldings {
    uint secToExpiry;
    StrikeHolding[] options;
    uint forwardPrice;
    uint volShockUp;
    uint volShockDown;
    int mtm;
    int fwdShock1MtM;
    int fwdShock2MtM;
    uint staticDiscount;
    int64 rate;
    uint64 discountFactor;
    uint minConfidence;
    uint netOptions;
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
    uint expiry;
    uint optionCount;
  }

  struct Scenario {
    uint spotShock; // i.e. 1.2e18 = 20% spot shock up
    VolShockDirection volShock; // i.e. [Up, Down, None]
  }
}
