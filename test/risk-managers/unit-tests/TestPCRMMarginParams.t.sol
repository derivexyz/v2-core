pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "test/feeds/mocks/MockV3Aggregator.sol";
import "src/feeds/ChainlinkSpotFeeds.sol";
import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/assets/CashAsset.sol";
import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockSM.sol";
import "test/risk-managers/mocks/MockSpotJumpOracle.sol";

import "test/risk-managers/mocks/MockDutchAuction.sol";

contract PCRMTester is PCRM {
  constructor(
    IAccounts accounts_,
    ISpotFeeds spotFeeds_,
    ICashAsset cashAsset_,
    IOption option_,
    address auction_,
    ISpotJumpOracle spotJumpOracle_
  ) PCRM(accounts_, spotFeeds_, cashAsset_, option_, auction_, spotJumpOracle_) {}

  function getMarginParams(
    uint spotUpPercent, uint spotDownPercent, uint spotTimeSlope, uint portfolioDiscountFactor, int timeToExpiry
  ) external view returns (uint vol, uint spotUp, uint spotDown, uint portfolioDiscount) {
    return _getMarginParams(spotUpPercent, spotDownPercent, spotTimeSlope, portfolioDiscountFactor, timeToExpiry);
  }

  function getSpotShocks(uint spot, uint spotUpPercent, uint spotDownPercent, uint timeSlope, uint timeToExpiry)
    external pure returns (uint up, uint down) {
    return _getSpotShocks(spot, spotUpPercent, spotDownPercent, timeSlope, timeToExpiry);
  }

  function getVol(uint timeToExpiry) external view returns (uint vol) {
    return _getVol(timeToExpiry);
  }

  function getSpotJumpMultiple(uint spotJumpSlope, uint32 lookbackLength) external returns (uint multiple) {
    return _getSpotJumpMultiple(spotJumpSlope, lookbackLength);
  }

  function getPortfolioDiscount(uint staticDiscount, uint timeToExpiry) external view returns (uint expiryDiscount) {
    return _getPortfolioDiscount(staticDiscount, timeToExpiry);
  }
}

contract UNIT_TestPCRM is Test {
  Accounts account;
  PCRMTester manager;
  MockAsset cash;
  MockERC20 usdc;

  ChainlinkSpotFeeds spotFeeds; //todo: should replace with generic mock
  MockSpotJumpOracle spotJumpOracle;
  MockV3Aggregator aggregator;
  MockOption option;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);
    usdc = new MockERC20("USDC", "USDC");

    option = new MockOption(account);
    cash = new MockAsset(usdc, account, true);
    spotJumpOracle = new MockSpotJumpOracle();

    manager = new PCRMTester(
      account,
      ISpotFeeds(address(spotFeeds)),
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
        riskFreeRate: 10e16 // 10%
      })
    );
  }

  ////////////////////////
  // Portfolio Discount //
  ////////////////////////

  function testPortfolioDiscountIsTimeDependent() public {
    // case 1: 1 day, 50% initial discount
    assertApproxEqAbs(manager.getPortfolioDiscount(50e16, 1 days), 49.99e16, 1e14);

    // case 2: 7 day, 80% initial discount
    assertApproxEqAbs(manager.getPortfolioDiscount(80e16, 7 days), 79.85e16, 1e14);

    // case 3: 1 month, 90% initial discount
    assertApproxEqAbs(manager.getPortfolioDiscount(90e16, 30 days), 89.26e16, 1e14);

    // case 4: 12 months, 20% initial discount
    assertApproxEqAbs(manager.getPortfolioDiscount(20e16, 365 days), 18.10e16, 1e14);

    // case 5: 36 months, 10% initial discount
    assertApproxEqAbs(manager.getPortfolioDiscount(10e16, 1095 days), 7.41e16, 1e14);
  }

  function testFuzzDiscountAlwaysIncreases(uint staticDiscount, uint timeToExpiry) public {
    vm.assume(staticDiscount < 1e18); 
    vm.assume(timeToExpiry >= 0);
    vm.assume(timeToExpiry < 50 * 365 days);
    assertGe(staticDiscount, manager.getPortfolioDiscount(staticDiscount, timeToExpiry));
  }
}