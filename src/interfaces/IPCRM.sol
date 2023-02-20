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
    // static cash requirement on top of the usual initial margin requirement
    uint initialStaticCashOffset;
    /// used when discounting to net present value by risk free rate
    uint riskFreeRate;
  }

  //////////////
  // External //
  //////////////

  function portfolioDiscountParams()
    external
    view
    returns (uint maintenance, uint initial, uint initialStaticCashOffset, uint riskFreeRate);

  function spotJumpOracle() external view returns (ISpotJumpOracle oracle);

  /// @dev return the portfolio struct in memory for a given account
  function getPortfolio(uint accountId) external view returns (Portfolio memory portfolio);

  /// @dev executes a liquidation bid which exchange cash for a portion of the account's position
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount, uint liquidatorFee) external;

  /// @dev returns the initial margin for a given portfolio
  function getInitialMargin(Portfolio memory portfolio) external view returns (int);

  /// @dev return the initial margin for a given portfolio, assuming realized vol is 0
  function getInitialMarginRVZero(Portfolio memory portfolio) external view returns (int);

  /// @dev returns the maintenance margin for a given portfolio
  function getMaintenanceMargin(Portfolio memory portfolio) external view returns (int);
}
