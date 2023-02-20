pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/IChainlinkSpotFeed.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/shared/mocks/MockFeed.sol";
import "test/risk-managers/mocks/MockSpotJumpOracle.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";

contract PCRMTester is PCRM {
  constructor(
    IAccounts accounts_,
    IChainlinkSpotFeed feed_,
    ICashAsset cashAsset_,
    IOption option_,
    address auction_,
    ISpotJumpOracle spotJumpOracle_
  ) PCRM(accounts_, feed_, feed_, cashAsset_, option_, auction_, spotJumpOracle_) {}

  function applyTimeWeightToSpotShocks(
    uint spot,
    uint spotUpPercent,
    uint spotDownPercent,
    uint timeSlope,
    uint timeToExpiry
  ) external pure returns (uint up, uint down) {
    return _applyTimeWeightToSpotShocks(spot, spotUpPercent, spotDownPercent, timeSlope, timeToExpiry);
  }

  function applyTimeWeightToVol(uint timeToExpiry) external view returns (uint vol) {
    return _applyTimeWeightToVol(timeToExpiry);
  }

  function applyTimeWeightToPortfolioDiscount(uint staticDiscount, uint timeToExpiry)
    external
    view
    returns (uint expiryDiscount)
  {
    return _applyTimeWeightToPortfolioDiscount(staticDiscount, timeToExpiry);
  }

  function getSpotJumpMultiple(uint spotJumpSlope, uint32 lookbackLength) external view returns (uint multiple) {
    return _getSpotJumpMultiple(spotJumpSlope, lookbackLength);
  }
}

contract UNIT_TimeWeightingPCRM is Test {
  Accounts account;
  PCRMTester manager;
  MockAsset cash;
  MockERC20 usdc;

  MockFeed feed;
  MockSpotJumpOracle spotJumpOracle;
  MockOption option;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    feed = new MockFeed();
    usdc = new MockERC20("USDC", "USDC");

    option = new MockOption(account);
    cash = new MockAsset(usdc, account, true);
    spotJumpOracle = new MockSpotJumpOracle();

    manager = new PCRMTester(
      account,
      feed,
      ICashAsset(address(cash)),
      option,
      address(0),
      ISpotJumpOracle(address(spotJumpOracle))
    );

    // cash.setWhitWelistManager(address(manager), true);
    manager.setParams(
      IPCRM.SpotShockParams({
        upInitial: 120e16,
        downInitial: 80e16,
        upMaintenance: 110e16,
        downMaintenance: 90e16,
        timeSlope: 1e18
      }),
      IPCRM.VolShockParams({
        minVol: 1e18,
        maxVol: 3e18,
        timeA: 30 days,
        timeB: 90 days,
        spotJumpMultipleSlope: 5e18,
        spotJumpMultipleLookback: 1 days
      }),
      IPCRM.PortfolioDiscountParams({
        maintenance: 90e16, // 90%
        initial: 80e16, // 80%
        initialStaticCashOffset: 0,
        riskFreeRate: 10e16 // 10%
      })
    );
  }

  ///////////////////////////
  // Computing Spot Shocks //
  ///////////////////////////

  function testGetSpotShocks() public {
    // case 1: < 1 year with 1x slope
    (uint up, uint down) = manager.applyTimeWeightToSpotShocks(1000e18, 1.2e18, 0.8e18, 1e18, 100 days);
    assertApproxEqAbs(up, 1473.9726e18, 1e14);
    assertApproxEqAbs(down, 526.027397e18, 1e14);

    // case 2: < 1 year with 2x slope
    (up, down) = manager.applyTimeWeightToSpotShocks(1000e18, 1.5e18, 0.5e18, 2e18, 30 days);
    assertApproxEqAbs(up, 1664.38356e18, 1e14);
    assertApproxEqAbs(down, 335.616438e18, 1e14);

    // case 3: > 1 year with down hitting zero
    (up, down) = manager.applyTimeWeightToSpotShocks(2e18, 1.1e18, 0.1e18, 5e18, 500 days);
    assertApproxEqAbs(up, 15.89863e18, 1e14);
    assertApproxEqAbs(down, 0, 1e14);

    // case 4: 0 days
    (up, down) = manager.applyTimeWeightToSpotShocks(100e18, 1.1e18, 0.9e18, 100e18, 0 days);
    assertApproxEqAbs(up, 110e18, 1e14);
    assertApproxEqAbs(down, 90e18, 1e14);

    // case 5: tiny slope
    (up, down) = manager.applyTimeWeightToSpotShocks(1e18, 1.5e18, 0.5e18, 0.01e18, 365 days);
    assertApproxEqAbs(up, 1.51e18, 1e14);
    assertApproxEqAbs(down, 0.49e18, 1e14);

    // case 6: slope = 0
    (up, down) = manager.applyTimeWeightToSpotShocks(1e18, 1.5e18, 0.5e18, 0, 365 days);
    assertApproxEqAbs(up, 1.5e18, 1e14);
    assertApproxEqAbs(down, 0.5e18, 1e14);
  }

  ///////////////////
  // Computing Vol //
  ///////////////////

  function testGetVol() public {
    // case 1: before time A
    assertApproxEqAbs(manager.applyTimeWeightToVol(1 days), 3e18, 1e14);

    // case 2: after time B
    assertApproxEqAbs(manager.applyTimeWeightToVol(91 days), 1e18, 1e14);

    // case 3: right in the middle
    assertApproxEqAbs(manager.applyTimeWeightToVol(60 days), 2e18, 1e14);

    // case 4: between A and B
    assertApproxEqAbs(manager.applyTimeWeightToVol(35 days), 2.8333e18, 1e14);

    // case 5: between A and B
    assertApproxEqAbs(manager.applyTimeWeightToVol(79 days), 1.3666e18, 1e14);
  }

  function testFuzzNeverBeyondMinOrMaxVol(uint timeToExpiry) public {
    (uint minVol, uint maxVol,,,,) = manager.volShockParams();

    // vm.assume(timeToExpiry < 100e18);
    assertGe(manager.applyTimeWeightToVol(timeToExpiry), minVol);
    assertLe(manager.applyTimeWeightToVol(timeToExpiry), maxVol);
  }

  ////////////////////////
  // Portfolio Discount //
  ////////////////////////

  function testPortfolioDiscountIsTimeDependent() public {
    // case 1: 1 day, 50% initial discount
    assertApproxEqAbs(manager.applyTimeWeightToPortfolioDiscount(50e16, 1 days), 49.99e16, 1e14);

    // case 2: 7 day, 80% initial discount
    assertApproxEqAbs(manager.applyTimeWeightToPortfolioDiscount(80e16, 7 days), 79.85e16, 1e14);

    // case 3: 1 month, 90% initial discount
    assertApproxEqAbs(manager.applyTimeWeightToPortfolioDiscount(90e16, 30 days), 89.26e16, 1e14);

    // case 4: 12 months, 20% initial discount
    assertApproxEqAbs(manager.applyTimeWeightToPortfolioDiscount(20e16, 365 days), 18.1e16, 1e14);

    // case 5: 36 months, 10% initial discount
    assertApproxEqAbs(manager.applyTimeWeightToPortfolioDiscount(10e16, 1095 days), 7.41e16, 1e14);
  }

  function testFuzzDiscountAlwaysIncreases(uint staticDiscount, uint timeToExpiry) public {
    vm.assume(staticDiscount < 1e18);
    vm.assume(timeToExpiry >= 0);
    vm.assume(timeToExpiry < 50 * 365 days);
    assertGe(staticDiscount, manager.applyTimeWeightToPortfolioDiscount(staticDiscount, timeToExpiry));
  }

  ////////////////////////
  // Spot Jump Multiple //
  ////////////////////////

  function testSpotJumpMultiple() public {
    // case 1: slope: 2x, Max Jump: 0%
    spotJumpOracle.setMaxJump(0);
    assertApproxEqAbs(manager.getSpotJumpMultiple(2e18, 1 days), 1e18, 1e14);

    // case 2: slope: 1x, Max Jump: 5%
    spotJumpOracle.setMaxJump(500);
    assertApproxEqAbs(manager.getSpotJumpMultiple(2e18, 1 days), 1.1e18, 1e14);

    // case 3: slope: 5x, Max Jump: 20%,
    spotJumpOracle.setMaxJump(2000);
    assertApproxEqAbs(manager.getSpotJumpMultiple(5e18, 1 days), 2e18, 1e14);

    // case 4: slope: 0x, Max Jump: 10%,
    spotJumpOracle.setMaxJump(1000);
    assertApproxEqAbs(manager.getSpotJumpMultiple(0, 1 days), 1e18, 1e14);

    // case 5: slope: 0.5x, Max Jump: 10%,
    spotJumpOracle.setMaxJump(1000);
    assertApproxEqAbs(manager.getSpotJumpMultiple(5e17, 1 days), 1.05e18, 1e14);
  }

  function testFuzzMultipleAlwaysAboveZero(uint32 maxJump, uint slope) public {
    vm.assume(slope < 100e18);

    spotJumpOracle.setMaxJump(maxJump);
    assertGe(manager.getSpotJumpMultiple(slope, 1 days), 1e18);
  }
}
