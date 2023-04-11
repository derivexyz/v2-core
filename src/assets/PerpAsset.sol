// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console2.sol";

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "lyra-utils/ownership/Owned.sol";
import "lyra-utils/math/IntLib.sol";

import "src/interfaces/IAccounts.sol";
import "src/interfaces/IPerpAsset.sol";
import "src/interfaces/IChainlinkSpotFeed.sol";

import "./ManagerWhitelist.sol";

/**
 * @title PerpAsset
 * @author Lyra
 * @dev settlement refers to the action initiate by the manager that print / burn cash based on accounts' PNL and funding
 *      this contract keep track of users' pending funding and PNL, during trades
 *      and update them when settlement is called
 */
contract PerpAsset is IPerpAsset, Owned, ManagerWhitelist {
  using SafeERC20 for IERC20Metadata;
  using SignedMath for int;
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  IChainlinkSpotFeed public spotFeed;

  ///@dev mapping from account to position
  mapping(uint => PositionDetail) public positions;

  ///@dev mapping from address to whitelisted to push impacted prices
  address public impactPriceOracle;

  /// @dev max hourly funding rate
  int immutable maxRatePerHour;
  /// @dev min hourly funding rate
  int immutable minRatePerHour;

  /// @dev current hourly premium rate
  int128 public premium;
  /// @dev static hourly interest rate to borrow base asset, used to calculate funding
  int128 public staticInterestRate;

  ///@dev latest aggregated funding rate
  int public aggregatedFundingRate;

  ///@dev last time aggregated funding rate was updated
  uint public lastFundingPaidAt;

  constructor(IAccounts _accounts, int maxAbsRatePerHour) ManagerWhitelist(_accounts) {
    lastFundingPaidAt = block.timestamp;

    maxRatePerHour = maxAbsRatePerHour;
    minRatePerHour = -maxAbsRatePerHour;
  }

  //////////////////////////
  // Owner Only Functions //
  //////////////////////////

  /**
   * @notice Set new spot feed address
   * @param _spotFeed address of the new spot feed
   */
  function setSpotFeed(IChainlinkSpotFeed _spotFeed) external onlyOwner {
    spotFeed = _spotFeed;

    emit SpotFeedUpdated(address(_spotFeed));
  }

  /**
   * @notice Set impact price oracle address that can update impact prices
   * @param _oracle address of the new impact price oracle
   */
  function setImpactPriceOracle(address _oracle) external onlyOwner {
    impactPriceOracle = _oracle;

    emit ImpactPriceOracleUpdated(_oracle);
  }

  /**
   * @notice Set new static interest rate
   * @param _staticInterestRate New static interest rate for the asset. Should be lower than
   */
  function setStaticInterestRate(int128 _staticInterestRate) external onlyOwner {
    if (_staticInterestRate < 0) revert PA_InvalidStaticInterestRate();
    staticInterestRate = _staticInterestRate;

    emit StaticUnderlyingInterestRateUpdated(_staticInterestRate);
  }

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
  ) external onlyAccount returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));

    // calculate funding from the last period, reflect changes in position.funding
    _updateFundingRate();

    // update average entry price
    _updateEntryPriceAndPnl(adjustment.acc, preBalance, adjustment.amount);

    // have a new position
    finalBalance = preBalance + adjustment.amount;

    needAllowance = true;
  }

  /**
   * @dev update the entry price if an account is increased
   *      and update the PnL if the position is closed
   */
  function _updateEntryPriceAndPnl(uint accountId, int preBalance, int delta) internal {
    PositionDetail storage position = positions[accountId];

    int indexPrice = spotFeed.getSpot().toInt256();

    int entryPrice = position.entryPrice.toInt256();

    int pnl;

    if (preBalance == 0) {
      // if position was empty, update entry price
      entryPrice = indexPrice;
    } else if (preBalance * delta > 0) {
      // pre-balance and delta has the same sign: increase position
      // if position increases: modify entry price
      entryPrice = (entryPrice * preBalance + indexPrice * delta) / (preBalance + delta);
    } else if (preBalance.abs() >= delta.abs()) {
      pnl = (entryPrice - indexPrice).multiplyDecimal(delta);
    } else {
      // position flipped from + to -, or - to +
      pnl = (indexPrice - entryPrice).multiplyDecimal(preBalance);
      entryPrice = indexPrice;
    }

    position.entryPrice = uint(entryPrice);
    position.pnl += pnl;
  }

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint, /*accountId*/ IManager newManager) external view {
    _checkManager(address(newManager));
  }

  //////////////////////////
  // Privileged Functions //
  //////////////////////////

  /**
   * @dev manager-only function to clear pnl and funding during settlement
   * @param accountId Account Id to settle
   */
  function settleRealizedPNLAndFunding(uint accountId) external returns (int netCash) {
    if (msg.sender != address(accounts.manager(accountId))) revert PA_WrongManager();

    PositionDetail storage position = positions[accountId];
    netCash = position.funding + position.pnl;

    position.funding = 0;
    position.pnl = 0;

    return netCash;
  }

  /**
   * @notice This function is called by the keeper to update premium used for funding rate
   * @param _premium premium rate: should be impacted bid diff - impact ask diff, 18 decimals
   */
  function setPremium(int128 _premium) external onlyImpactPriceOracle {
    premium = _premium;

    _updateFundingRate();

    emit PremiumUpdated(premium);
  }

  //////////////////////
  // Public Functions //
  //////////////////////

  /**
   * @dev Update funding rate, reflected on aggregatedFundingRate
   */
  function updateFundingRate() external {
    _updateFundingRate();
  }

  /**
   * @dev Update funding rate, reflected on aggregatedFundingRate
   */
  function _updateFundingRate() internal {
    int fundingRate = _getFundingRate();

    int timeElapsed = (block.timestamp - lastFundingPaidAt).toInt256();

    aggregatedFundingRate += fundingRate * timeElapsed / 1 hours;
  }

  /**
   * @notice This function update funding for an account and apply to position detail
   * @param accountId Account Id to apply funding
   */
  function applyFundingOnAccount(uint accountId) external {
    _applyFundingOnAccount(accountId);
  }

  /**
   * Funding per Hour = (-1) × S × P × R
   * Where:
   *
   * S is the size of the position (positive if long, negative if short)
   * P is the oracle (index) price for the market
   * R is the funding rate (as a 1-hour rate)
   *
   * @param accountId Account Id to apply funding
   */
  function _applyFundingOnAccount(uint accountId) internal {
    int size = _getPositionSize(accountId);
    int indexPrice = spotFeed.getSpot().toInt256();

    int funding = _getUnrealizedFunding(accountId, size, indexPrice);
    // apply funding
    positions[accountId].funding += funding;
    positions[accountId].lastAggregatedFundingRate = aggregatedFundingRate;
  }

  /**
   * @dev This function reflect how much cash should be mark "available" for an account
   * @return totalCash is the sum of total funding, realized PNL and unrealized PNL
   */
  function getUnsettledAndUnrealizedCash(uint accountId) external view returns (int totalCash) {
    int size = _getPositionSize(accountId);
    int indexPrice = spotFeed.getSpot().toInt256();

    int unrealizedFunding = _getUnrealizedFunding(accountId, size, indexPrice);
    int unrealizedPnl = _getUnrealizedPnl(accountId, size, indexPrice);
    return unrealizedFunding + unrealizedPnl + positions[accountId].funding + positions[accountId].pnl;
  }

  /**
   * @notice return hourly funding rate
   */
  function getFundingRate() external view returns (int) {
    return _getFundingRate();
  }

  /**
   * @dev Get unrealized funding if applyFunding is called now
   */
  function _getUnrealizedFunding(uint accountId, int size, int indexPrice) internal view returns (int funding) {
    PositionDetail storage position = positions[accountId];

    int rateToPay = aggregatedFundingRate - position.lastAggregatedFundingRate;

    funding = -size.multiplyDecimal(indexPrice).multiplyDecimal(rateToPay);
  }

  /**
   * @dev Get unrealized PNL if the position is closed at the current spot price
   */
  function _getUnrealizedPnl(uint accountId, int size, int indexPrice) internal view returns (int) {
    int entryPrice = positions[accountId].entryPrice.toInt256();

    return (indexPrice - entryPrice).multiplyDecimal(size);
  }

  /**
   * @dev Get number of contracts open, with 18 decimals
   */
  function _getPositionSize(uint accountId) internal view returns (int) {
    return accounts.getBalance(accountId, IPerpAsset(address(this)), 0);
  }

  /**
   * @dev Get the hourly funding rate based on index price and impact market prices
   */
  function _getFundingRate() internal view returns (int fundingRate) {
    fundingRate = int(premium / 8 + staticInterestRate);

    // capped at max / min
    if (fundingRate > maxRatePerHour) {
      fundingRate = maxRatePerHour;
    } else if (fundingRate < minRatePerHour) {
      fundingRate = minRatePerHour;
    }
  }

  //////////////////////////
  //     Modifiers        //
  //////////////////////////

  modifier onlyImpactPriceOracle() {
    if (msg.sender != impactPriceOracle) revert PA_OnlyImpactPriceOracle();
    _;
  }
}
