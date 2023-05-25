// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";

import "lyra-utils/decimals/SignedDecimalMath.sol";
import "lyra-utils/decimals/DecimalMath.sol";
import "openzeppelin/access/Ownable2Step.sol";
import "lyra-utils/math/IntLib.sol";

import {IAccounts} from "src/interfaces/IAccounts.sol";
import {IPerpAsset} from "src/interfaces/IPerpAsset.sol";
import {ISpotFeed} from "src/interfaces/ISpotFeed.sol";

import {IManager} from "src/interfaces/IManager.sol";

import "./ManagerWhitelist.sol";

import "./OITracking.sol";

/**
 * @title PerpAsset
 * @author Lyra
 * @dev settlement refers to the action initiate by the manager that print / burn cash based on accounts' PNL and funding
 *      this contract keep track of users' pending funding and PNL, during trades
 *      and update them when settlement is called
 */
contract PerpAsset is IPerpAsset, OITracking, ManagerWhitelist {
  using SafeERC20 for IERC20Metadata;
  using SignedMath for int;
  using SafeCast for uint;
  using SafeCast for int;
  using SignedDecimalMath for int;
  using DecimalMath for uint;

  ///@dev spot feed, used to determine funding by comparing index to impactAsk or impactBid
  ISpotFeed public spotFeed;

  ///@dev perp feed, used for settling pnl before each trades
  ISpotFeed public perpFeed;

  ///@dev Mapping from account to position
  mapping(uint account => PositionDetail) public positions;

  ///@dev Mapping from address to whitelisted to push impacted prices
  address public fundingRateOracle;

  /// @dev Max hourly funding rate
  int public immutable maxRatePerHour;

  /// @dev Min hourly funding rate
  int public immutable minRatePerHour;

  /// @dev Impact ask price
  int128 public impactAskPrice;

  /// @dev Impact bid price
  int128 public impactBidPrice;

  /// @dev static hourly interest rate to borrow base asset, used to calculate funding
  int128 public staticInterestRate;

  ///@dev Latest aggregated funding rate
  int128 public aggregatedFundingRate;

  ///@dev Last time aggregated funding rate was updated
  uint64 public lastFundingPaidAt;

  constructor(IAccounts _accounts, int maxAbsRatePerHour) ManagerWhitelist(_accounts) {
    lastFundingPaidAt = uint64(block.timestamp);

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
  function setSpotFeed(ISpotFeed _spotFeed) external onlyOwner {
    spotFeed = _spotFeed;

    emit SpotFeedUpdated(address(_spotFeed));
  }

  /**
   * @notice Set new perp feed address
   * @param _perpFeed address of the new perp feed
   */
  function setPerpFeed(ISpotFeed _perpFeed) external onlyOwner {
    perpFeed = _perpFeed;

    emit PerpFeedUpdated(address(_perpFeed));
  }

  /**
   * @notice Set an oracle address that can update funding rate
   * @param _oracle address of the new funding rate oracle
   */
  function setFundingRateOracle(address _oracle) external onlyOwner {
    fundingRateOracle = _oracle;

    emit FundingRateOracleUpdated(_oracle);
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
    IAccounts.AssetAdjustment memory adjustment,
    uint tradeId,
    int preBalance,
    IManager manager,
    address /*caller*/
  ) external onlyAccounts returns (int finalBalance, bool needAllowance) {
    _checkManager(address(manager));

    _takeOISnapshotPreTrade(adjustment.subId, tradeId);

    _updateOIAndTotalPosition(manager, adjustment.subId, preBalance, adjustment.amount);

    // calculate funding from the last period, reflect changes in position.funding
    _updateFundingRate();

    // update last index price and settle unrealized pnl into position.pnl
    _realizePNLWithIndex(adjustment.acc, preBalance);

    // have a new position
    finalBalance = preBalance + adjustment.amount;

    needAllowance = true;
  }

  /**
   * @notice Triggered when a user wants to migrate an account to a new manager
   * @dev block update with non-whitelisted manager
   */
  function handleManagerChange(uint accountId, IManager newManager) external onlyAccounts {
    _checkManager(address(newManager));

    // update total position
    uint pos = accounts.getBalance(accountId, IPerpAsset(address(this)), 0).abs();
    totalPosition[accounts.manager(accountId)] -= pos;
    totalPosition[newManager] += pos;

    uint cap = totalPositionCap[newManager];
    if (cap != 0 && totalPosition[newManager] > cap) revert PA_ManagerChangeExceedCap();
  }

  //////////////////////////
  // Privileged Functions //
  //////////////////////////

  /**
   * @notice Manager-only function to clear pnl and funding before risk checks
   * @dev The manager should then update the cash balance of an account base on the returned values
   *      Only meaningful to call this function after a perp asset transfer, otherwise it will be 0.
   * @param accountId Account Id to settle
   */
  function settleRealizedPNLAndFunding(uint accountId)
    external
    onlyManagerForAccount(accountId)
    returns (int pnl, int funding)
  {
    return _clearRealizedPNL(accountId);
  }

  /**
   * @notice allow oracle to set impact prices
   */
  function setImpactPrices(int128 _impactAskPrice, int128 _impactBidPrice) external onlyImpactPriceOracle {
    if (_impactAskPrice < 0 || _impactBidPrice < 0) {
      revert PA_ImpactPriceMustBePositive();
    }
    if (_impactAskPrice < _impactBidPrice) {
      revert PA_InvalidImpactPrices();
    }
    impactAskPrice = _impactAskPrice;
    impactBidPrice = _impactBidPrice;

    emit ImpactPricesSet(_impactAskPrice, _impactBidPrice);
  }

  /**
   * @notice Set new static interest rate
   * @param _staticInterestRate New static interest rate for the asset.
   */
  function setStaticInterestRate(int128 _staticInterestRate) external onlyOwner {
    if (_staticInterestRate < 0) revert PA_InvalidStaticInterestRate();
    staticInterestRate = _staticInterestRate;

    emit StaticUnderlyingInterestRateUpdated(_staticInterestRate);
  }

  //////////////////////
  // Public Functions //
  //////////////////////

  /**
   * @notice This function update funding for an account and apply to position detail
   * @param accountId Account Id to apply funding
   */
  function applyFundingOnAccount(uint accountId) external {
    _updateFundingRate();
    _applyFundingOnAccount(accountId);
  }

  /**
   * @notice a public function to settle position with index, update lastIndex price and move
   * @param accountId Account Id to settle
   */
  function realizePNLWithIndex(uint accountId) external {
    _realizePNLWithIndex(accountId, _getPositionSize(accountId));
  }

  /**
   * @dev This function reflect how much cash should be mark "available" for an account
   * @return totalCash is the sum of total funding, realized PNL and unrealized PNL
   */
  function getUnsettledAndUnrealizedCash(uint accountId) external view returns (int totalCash) {
    int size = _getPositionSize(accountId);
    int indexPrice = _getIndexPrice();
    int perpPrice = _getPerpPrice();

    int unrealizedFunding = _getUnrealizedFunding(accountId, size, indexPrice);
    int unrealizedPnl = _getUnrealizedPnl(accountId, size, perpPrice);
    return unrealizedFunding + unrealizedPnl + positions[accountId].funding + positions[accountId].pnl;
  }

  /**
   * @dev Return the hourly funding rate for an account
   */
  function getFundingRate() external view returns (int fundingRate) {
    int indexPrice = _getIndexPrice();
    fundingRate = _getFundingRate(indexPrice);
  }

  /**
   * @dev Return the current index price for the perp asset
   */
  function getIndexPrice() external view returns (uint) {
    (uint spotPrice,) = spotFeed.getSpot();
    return spotPrice;
  }

  /**
   * @dev Return the current mark price for the perp asset
   */
  function getPerpPrice() external view returns (uint) {
    (uint perpPrice,) = perpFeed.getSpot();
    return perpPrice;
  }

  /**
   * @notice real perp position pnl based on current index price
   * @dev This function will update position.PNL, but not initiate any real payment in cash
   */
  function _realizePNLWithIndex(uint accountId, int preBalance) internal {
    PositionDetail storage position = positions[accountId];

    int perpPrice = _getPerpPrice();
    int pnl = _getUnrealizedPnl(accountId, preBalance, perpPrice);

    position.lastMarkPrice = uint(perpPrice).toUint128();
    position.pnl += pnl.toInt128();
  }

  /**
   * @notice return pnl and funding kept in position storage and clear storage
   */
  function _clearRealizedPNL(uint accountId) internal returns (int pnl, int funding) {
    _updateFundingRate();
    _applyFundingOnAccount(accountId);

    PositionDetail storage position = positions[accountId];
    pnl = position.pnl;
    funding = position.funding;

    position.funding = 0;
    position.pnl = 0;
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
    int indexPrice = _getIndexPrice();

    int funding = _getUnrealizedFunding(accountId, size, indexPrice);
    // apply funding
    positions[accountId].funding += funding.toInt128();
    positions[accountId].lastAggregatedFundingRate = aggregatedFundingRate;
  }

  /**
   * @dev Update funding rate, reflected on aggregatedFundingRate
   */
  function _updateFundingRate() internal {
    if (block.timestamp == lastFundingPaidAt) return;

    int indexPrice = _getIndexPrice();

    int fundingRate = _getFundingRate(indexPrice);

    int timeElapsed = (block.timestamp - lastFundingPaidAt).toInt256();

    aggregatedFundingRate += (fundingRate * timeElapsed / 1 hours).toInt128();

    lastFundingPaidAt = (block.timestamp).toUint64();
  }

  /**
   * @dev return the hourly funding rate
   */
  function _getFundingRate(int indexPrice) internal view returns (int fundingRate) {
    int premium = _getPremium(indexPrice);
    fundingRate = premium / 8 + staticInterestRate;

    // capped at max / min
    if (fundingRate > maxRatePerHour) {
      fundingRate = maxRatePerHour;
    } else if (fundingRate < minRatePerHour) {
      fundingRate = minRatePerHour;
    }
  }

  /**
   * @dev get premium to calculate funding rate
   * Premium = (Max(0, Impact Bid Price - Index Price) - Max(0, Index Price - Impact Ask Price)) / Index Price
   */
  function _getPremium(int indexPrice) internal view returns (int premium) {
    premium = (
      SignedMath.max(int(impactBidPrice) - indexPrice, 0) - SignedMath.max(int(indexPrice) - impactAskPrice, 0)
    ).divideDecimal(indexPrice);
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
  function _getUnrealizedPnl(uint accountId, int size, int perpPrice) internal view returns (int) {
    int lastMarkPrice = uint(positions[accountId].lastMarkPrice).toInt256();

    return (perpPrice - lastMarkPrice).multiplyDecimal(size);
  }

  /**
   * @dev Get number of contracts open, with 18 decimals
   */
  function _getPositionSize(uint accountId) internal view returns (int) {
    return accounts.getBalance(accountId, IPerpAsset(address(this)), 0);
  }

  function _getIndexPrice() internal view returns (int) {
    (uint spotPrice,) = spotFeed.getSpot();
    return spotPrice.toInt256();
  }

  function _getPerpPrice() internal view returns (int) {
    (uint perpPrice,) = perpFeed.getSpot();
    return perpPrice.toInt256();
  }

  //////////////////////////
  //     Modifiers        //
  //////////////////////////

  modifier onlyImpactPriceOracle() {
    if (msg.sender != fundingRateOracle) revert PA_OnlyImpactPriceOracle();
    _;
  }

  modifier onlyManagerForAccount(uint accountId) {
    if (msg.sender != address(accounts.manager(accountId))) revert PA_WrongManager();
    _;
  }
}
