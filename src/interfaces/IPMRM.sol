interface IPMRM {
  enum VolShockDirection {
    None,
    Up,
    Down
  }

  struct PMRMParameters {
    int staticDiscount;
    int lossFactor;
    uint epsilon;
    uint fwdStep;
    int netPosScalar;
    uint pegLossFactor;
  }

  struct VolShockParameters {
    uint volRangeUp;
    uint volRangeDown;
    uint shortTermPower;
    uint longTermPower;
  }

  struct ContingencyParameters {
    uint basePercent;
    uint perpPercent;
    uint optionPercent;
    uint fwdSpotShock1;
    uint fwdSpotShock2;
    uint fwdScalingFactor;
    // <7 dte
    uint fwdShortFactor;
    // >7dte <28dte
    uint fwdMediumFactor;
    // >28dte
    uint fwdLongFactor;
    uint oracleConfMargin;
    uint oracleSpotConfThreshold;
    uint oracleVolConfThreshold;
    uint oracleFutureConfThreshold;
    uint oracleDiscountConfThreshold;
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
    int totalContingency;
    uint minConfidence;
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
    uint64 discountFactor;
    uint minConfidence;
  }

  struct StrikeHolding {
    /// strike price of held options
    uint strike;
    uint vol;
    int amount;
    bool isCall;
    uint minConfidence;
  }

  struct PortfolioExpiryData {
    uint expiry;
    uint callCount;
    uint putCount;
  }

  struct Scenario {
    uint spotShock; // i.e. 1.2e18 = 20% spot shock up
    VolShockDirection volShock; // i.e. [Up, Down, None]
  }
}
