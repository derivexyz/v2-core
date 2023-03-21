// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/ownership/Owned.sol";

import "./ManagerWhitelist.sol";

import "../interfaces/IAccounts.sol";
import "../interfaces/IPerpAsset.sol";

/**
 * @title PerpAsset
 * @author Lyra
 */
contract PerpAsset is IPerpAsset, Owned, ManagerWhitelist {
  using SafeERC20 for IERC20Metadata;
  using SignedMath for int;
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  constructor(IAccounts _accounts) ManagerWhitelist(_accounts) {}

  mapping (address => PositionDetail) public positions;

  ///@dev perp shock is 5%
  uint constant perpShock = 0.05e18; 

  ///@dev INA stans for initial notional amount => 2500 contracts
  uint constant INA = 2500e18;

  int constant MAX_RATE_PER_HOUR = 0.0075e18; // 0.75% per hour
  int constant MIN_RATE_PER_HOUR = -0.0075e18; // 0.75% per hour

  //////////////////////////
  //    Account Hooks     //
  //////////////////////////

  /**
   * @notice This function is called by the Account contract whenever a PerpAsset balance is modified.
   * @dev    This function will close existing positions, and open new ones based on new entry price
   * @param adjustment Details about adjustment, containing account, subId, amount
   * @param preBalance Balance before adjustment
   * @param manager The manager contract that will verify the end state
   * @return finalBalance The final balance to be recorded in the account
   * @return needAllowance Return true if this adjustment should assume allowance in Account
   */
  function handleAdjustment(
    AccountStructs.AssetAdjustment memory adjustment,
    uint, /*tradeId*/
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external view onlyAccount returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));

    // get market price
    // uint markPrice = manager.getMarkPrice(adjustment.account, adjustment.subId);

    // uint indexPrice = manager.getIndexPrice(adjustment.account, adjustment.subId);

    // settle the existing position for an user
    // updating USDC in account again?

    // have a new position
    finalBalance = preBalance + adjustment.amount;

    needAllowance = adjustment.amount < 0;
  }

  /**
   * F = (-1) × S × P × R
   * Where:

   * S is the size of the position (positive if long, negative if short)
   * P is the oracle (index) price for the market
   * R is the funding rate (as a 1-hour rate)

   * @return funding in cash, 18 decimals
   */
  function _calculateFundingPayment(int position) internal returns (int) {
    
    int indexPrice = 2100e18;

    int fundingRate = _getFundingRate(indexPrice);

    return -position * indexPrice * fundingRate;
    
  }

  function _getFundingRate(int indexPrice) internal view returns (int fundingRate) {
    int premium = _getPremium(indexPrice);
    fundingRate = premium / 8; // todo: plus interest rate

    // capped at max / min
    if (fundingRate > MAX_RATE_PER_HOUR) {
      fundingRate = MAX_RATE_PER_HOUR;
    } else if (fundingRate < MIN_RATE_PER_HOUR) {
      fundingRate = MIN_RATE_PER_HOUR;
    }
  }

  /**
   * @dev get premium to calculate funding rate
   * Premium = (Max(0, Impact Bid Price - Index Price) - Max(0, Index Price - Impact Ask Price)) / Index Price
   */
  function _getPremium(int indexPrice) internal view returns (int premium) {
    (int impactBidPrice, int impactAskPrice) = _getImpactPrices();

    premium = (SignedMath.max(impactBidPrice - indexPrice, 0) - SignedMath.max(indexPrice - impactAskPrice, 0))
      .divideDecimal(indexPrice);
  }

  /**
   * @dev Get IBP (Impact Bid Price) and IAP (Impact Ask Price)
   * Impact Bid Price = Average execution price for a market sell of the impact notional value 
   * Impact Ask Price = Average execution price for a market buy of the impact notional value
   */
  function _getImpactPrices() internal view returns (int, int) {

    uint marketPrice = 2000e18;
    // todo: consider INA, or this from the oracle directly
    int impactBidPrice = marketPrice.multiplyDecimal(1e18 - perpShock).toInt256();
    int impactAskPrice = marketPrice.multiplyDecimal(1e18 + perpShock).toInt256();

    return (impactBidPrice, impactAskPrice);
  } 

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    _checkManager(address(newManager));
  }
}
