// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/interfaces/IPCRM.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccounts.sol";

import "openzeppelin/utils/math/SafeMath.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/utils/math/SignedMath.sol";
import "test/risk-managers/mocks/MockSpotJumpOracle.sol";
import "lyra-utils/decimals/DecimalMath.sol";

// forge testing
import "forge-std/Test.sol";

contract MockIPCRM is IPCRM, IManager {
  using SafeCast for int;
  using SafeCast for uint;
  using DecimalMath for uint;

  address account;

  mapping(uint => bool) public accHasAssets;

  ISpotJumpOracle public spotJumpOracle;

  // next init margin that should be returned when calling getInitialMargin
  int public mockedInitMarginForPortfolio;
  // next init margin that should be returned when calling getInitialMargin, if portfolio passed in is inversed
  int public mockedInitMarginForPortfolioInversed;

  // next maintenance margin that should be returned when calling getMaintenanceMargin
  int public mockedMaintenanceMarginForPortfolio;

  // next margin that should be returned when calling getInitialMarginWithoutJumpMultiple
  int public mockedInitMarginZeroRV;

  Portfolio public userAcc; // just a result that can be set to be returned when testing

  // if set to true, assume next executeBid will bring init margin to 0
  bool nextIsEndingBid = false;

  bool revertGetMargin = false;

  constructor(address _account) {
    account = _account;
    spotJumpOracle = new MockSpotJumpOracle();
  }

  function executeBid(uint, /*accountId*/ uint, /*liquidatorId*/ uint, /*portion*/ uint, /*cashAmount*/ uint)
    external
    virtual
  {
    if (nextIsEndingBid) {
      nextIsEndingBid = false;
      mockedInitMarginZeroRV = 0;
    }
  }

  function setNextIsEndingBid() external {
    nextIsEndingBid = true;
  }

  function getPortfolio(uint accountId) external view virtual returns (Portfolio memory portfolio) {
    if (accHasAssets[accountId]) {
      Strike[] memory strikeHoldings = new Strike[](4);

      strikeHoldings[0] = Strike(1000, 1, 1, 1);
      strikeHoldings[1] = Strike(2000, 3, -1, 1);
      strikeHoldings[2] = Strike(3000, 4, -2, 1);
      strikeHoldings[3] = Strike(4000, 5, 10, 1);

      portfolio = Portfolio(0, block.timestamp + 2 weeks, 4, strikeHoldings);
    }
  }

  function handleAdjustment(
    uint, /*accountId*/
    uint, /*tradeId*/
    address, /*caller*/
    AccountStructs.AssetDelta[] memory, /*deltas*/
    bytes memory /*data*/
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

  function setInitMarginForPortfolio(int margin) external {
    mockedInitMarginForPortfolio = margin;
  }

  function setInitMarginForInversedPortfolio(int margin) external {
    mockedInitMarginForPortfolioInversed = margin;
  }

  function setInitMarginForPortfolioZeroRV(int margin) external {
    mockedInitMarginZeroRV = margin;
  }

  function setMaintenanceMarginForPortfolio(int margin) external {
    mockedMaintenanceMarginForPortfolio = margin;
  }

  function getInitialMargin(IPCRM.Portfolio memory portfolio) external view returns (int) {
    if (revertGetMargin) revert("mocked revert");
    // default is strikes[0] = {1000, 1 call, 1 put, 0 forward}
    if (portfolio.strikes.length == 0) revert("Please give portfolio to account first!");
    if (portfolio.strikes[0].calls > 0) {
      return mockedInitMarginForPortfolio;
    } else {
      return mockedInitMarginForPortfolioInversed;
    }
  }

  function getMaintenanceMargin(IPCRM.Portfolio memory) external view returns (int) {
    if (revertGetMargin) revert("mocked revert");
    return mockedMaintenanceMarginForPortfolio;
  }

  function getInitialMarginWithoutJumpMultiple(IPCRM.Portfolio memory) external view returns (int) {
    if (revertGetMargin) revert("mocked revert");
    return mockedInitMarginZeroRV;
  }

  function setRevertMargin() external {
    revertGetMargin = true;
  }

  function portfolioDiscountParams()
    external
    pure
    returns (uint maintenance, uint initial, uint initialStaticCashOffset, uint riskFreeRate)
  {
    return (80e16, 70e16, 50e18, 10e16);
  }

  function feeCharged(uint, /*tradeId*/ uint /*account*/ ) external pure returns (uint) {
    return 0;
  }

  function test() public {}
}
