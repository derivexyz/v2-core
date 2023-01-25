// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/interfaces/IPCRM.sol";
import "../../../src/interfaces/IManager.sol";
import "../../../src/interfaces/IAsset.sol";
import "../../../src/interfaces/IAccounts.sol";

import "../../../src/libraries/DecimalMath.sol";
import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";

// forge testing
import "forge-std/Test.sol";

contract MockIPCRM is IPCRM, IManager {
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;

  address account;

  mapping(uint => int) public initMargin;
  mapping(uint => bool) public accHasAssets;

  // next init margin that should be returned when calling getInitialMarginForPortfolio
  int public portMargin;
  Portfolio public userAcc; // just a result that can be set to be returned when testing

  // if set to true, assume next executeBid will bring init margin to 0
  bool nextIsEndingBid = false;

  constructor(address _account) {
    account = _account;
  }

  // TODO: needs to be expanded upon next sprint to make sure that
  // it can handle the insolvency case properly
  function executeBid(uint accountId, uint liquidatorId, uint portion, uint cashAmount)
    external
    virtual
    returns (int finalInitialMargin, Portfolio[] memory, int cash)
  {
    if (cashAmount > 0) {
      initMargin[accountId] += cashAmount.toInt256();
    }
    if (nextIsEndingBid) {
      nextIsEndingBid = false;
      initMargin[accountId] = 0;
    }

    // portMargin[accountId] = (portMargin[accountId] * portion.toInt256()) / 1e18;
  }

  function setNextIsEndingBid() external {
    nextIsEndingBid = true;
  }

  function getSpot() external view virtual returns (uint spot) {
    // TODO: filler code
    return 1000 * DecimalMath.UNIT;
  }

  function getAccountValue(uint accountId) external view virtual returns (uint) {
    // TODO: filler code
    return 0;
  }

  function getInitialMargin(uint accountId) external view virtual returns (int) {
    // TODO: filler code
    return initMargin[accountId];
  }

  function getMaintenanceMargin(uint accountId) external returns (uint) {
    // TODO: filler code
    return 0;
  }

  function getPortfolio(uint accountId) external view virtual returns (Portfolio memory portfolio) {
    // TODO: filler code
    if (accHasAssets[accountId]) {
      Strike[] memory strikeHoldings = new Strike[](4);

      strikeHoldings[0] = Strike(1000, 1, 1, 1);
      strikeHoldings[1] = Strike(2000, 3, -1, 1);
      strikeHoldings[2] = Strike(3000, 4, -2, 1);
      strikeHoldings[3] = Strike(4000, 5, 10, 1);

      portfolio = Portfolio(0, block.timestamp + 2 weeks, 4, strikeHoldings);
    }
  }

  function getCashAmount(uint accountId) external view virtual returns (int) {
    // TODO: filer coder
    return 0;
  }

  function handleAdjustment(
    uint accountId,
    uint, /*tradeId*/
    address caller,
    AccountStructs.AssetDelta[] memory deltas,
    bytes memory data
  ) external virtual {
    // TODO: filler code
  }

  /**
   * @notice triggered when a user want to change to a new manager
   * @dev    a manager should only allow migrating to another manager it trusts.
   */
  function handleManagerChange(uint accountId, IManager newManager) external {
    // TODO: filler code
  }

  function setAccInitMargin(uint accountId, int amount) external {
    initMargin[accountId] = amount;
  }

  function giveAssets(uint accountId) external {
    accHasAssets[accountId] = true;
  }

  function givePortfolio(uint accountId, Portfolio memory portfolio) external {
    accHasAssets[accountId] = true;

    userAcc.expiry = portfolio.expiry;
    userAcc.numStrikesHeld = portfolio.numStrikesHeld;
    for (uint i = 0; i < portfolio.strikes.length; i++) {
      userAcc.strikes[i].strike = portfolio.strikes[i].strike;
      userAcc.strikes[i].calls = portfolio.strikes[i].calls;
      userAcc.strikes[i].puts = portfolio.strikes[i].puts;
      userAcc.strikes[i].forwards = portfolio.strikes[i].forwards;
    }
  }

  function setMarginForPortfolio(int margin) external {
    portMargin = margin;
  }

  function getInitialMarginForPortfolio(IPCRM.Portfolio memory) external view returns (int) {
    return portMargin;
  }

  function test() public {}
}
