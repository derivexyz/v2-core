// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IBaseManager.sol";
import "src/interfaces/ISpotJumpOracle.sol";

/**
 * @title PartialCollateralRiskManager
 * @author Lyra
 * @notice Risk Manager that controls transfer and margin requirements
 */
interface IPCRM is IBaseManager {
  /////////////
  // Structs //
  /////////////

  /**
   * INITIAL: margin required for trade to pass
   * MAINTENANCE: margin required to prevent liquidation
   */
  enum MarginType {
    INITIAL,
    MAINTENANCE
  }

  struct SpotShockParams {
    /// high spot value used for initial margin
    uint upInitial;
    /// low spot value used for initial margin
    uint downInitial;
    /// high spot value used for maintenance margin
    uint upMaintenance;
    /// low spot value used for maintenance margin
    uint downMaintenance;
    /// rate at which the shocks increase with further timeToExpiry
    uint timeSlope;
  }

  struct VolShockParams {
    /* The vol shock is derived from the following chart:
     *
     *     vol
     *      |
     * max  |____
     *      |     \
     *      |      \
     * min  |       \ ___
     *      |____________  time to expiry
     *           A   B
     */
    /// smallest vol shock
    uint minVol;
    /// largest vol shock
    uint maxVol;
    /// sec to expiry at which vol begins to grow
    uint timeA;
    /// sec to expiry at which vol grow any further
    uint timeB;
    // todo: quite opinionated to assume we always take a jump input.
    //       ideally should just take RV in.
    //       may be able to find a way to put into a library or wrapper
    //       so that it can be reused in later deployments
    /// slope at which vol increases with jumps in spot price
    uint spotJumpMultipleSlope;
    /// how many seconds to look back when finding the max jump
    uint32 spotJumpMultipleLookback;
  }

  struct PortfolioDiscountParams {
    /// maintenance discount applied to whole expiry
    uint maintenance;
    /// initial discount applied to whole expiry
    uint initial;
    /// used when discounting to net present value by risk free rate
    uint riskFreeRate;
  }

  //////////////
  // External //
  //////////////

  function spotJumpOracle() external view returns (ISpotJumpOracle oracle);

  function getPortfolio(uint accountId) external view returns (Portfolio memory portfolio);

  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee) external;

  function getInitialMargin(Portfolio memory portfolio) external returns (int);

  /// @dev temporary function place holder to return RV = 0
  function getInitialMarginRVZero(Portfolio memory portfolio) external returns (int);

  function getMaintenanceMargin(Portfolio memory portfolio) external returns (int);
}
