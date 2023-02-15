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

  function getSpotJumpMultiple(uint spotJumpSlope, uint32 lookbackLength) external returns (uint multiple) {
    return _getSpotJumpMultiple(spotJumpSlope, lookbackLength);
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
  MockDutchAuction auction;
  MockSM sm;
  uint feeRecipient;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    aggregator = new MockV3Aggregator(18, 1000e18);
    spotFeeds = new ChainlinkSpotFeeds();
    spotFeeds.addFeed("ETH/USD", address(aggregator), 1 hours);
    usdc = new MockERC20("USDC", "USDC");

    auction = new MockDutchAuction();

    option = new MockOption(account);
    cash = new MockAsset(usdc, account, true);
    spotJumpOracle = new MockSpotJumpOracle();

    manager = new PCRMTester(
      account,
      ISpotFeeds(address(spotFeeds)),
      ICashAsset(address(cash)),
      option,
      address(auction),
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

    feeRecipient = account.createAccount(address(this), manager);

    vm.startPrank(alice);
    aliceAcc = account.createAccount(alice, IManager(manager));
    bobAcc = account.createAccount(bob, IManager(manager));
    vm.stopPrank();

    vm.startPrank(bob);
    account.approve(alice, bobAcc);
    vm.stopPrank();
  }

  ///////////
  // Admin //
  ///////////

  function testSetParamsWithNonOwner() public {
    vm.startPrank(alice);
    vm.expectRevert(AbstractOwned.OnlyOwner.selector);
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
    vm.stopPrank();
  }

  function testSetParamsWithOwner() public {
    manager.setParams(
      IPCRM.SpotShockParams({
        upInitial: 200e16,
        downInitial: 50e16,
        upMaintenance: 120e16,
        downMaintenance: 70e16,
        timeSlope: 1e18
      }),
      IPCRM.VolShockParams({
        minVol: 1e18,
        maxVol: 400e16,
        timeA: 30 days,
        timeB: 90 days,
        spotJumpMultipleSlope: 5e18,
        spotJumpMultipleLookback: 1 days
      }),
      IPCRM.PortfolioDiscountParams({
        maintenance: 85e16, // 90%
        initial: 75e16, // 80%
        riskFreeRate: 20e16 // 10%
      })
    );

    (uint spotUpInitial, uint spotDownInitial, uint spotUpMaintenance, uint spotDownMaintenance,) =
      manager.spotShockParams();
    assertEq(spotUpInitial, 200e16);
    assertEq(spotDownInitial, 50e16);
    assertEq(spotUpMaintenance, 120e16);
    assertEq(spotDownMaintenance, 70e16);

    (uint minVol, uint maxVol,,,,) = manager.volShockParams();
    assertEq(minVol, 1e18);
    assertEq(maxVol, 400e16);

    (uint maintenance, uint initial, uint riskFreeRate) = manager.portfolioDiscountParams();
    assertEq(maintenance, 85e16);
    assertEq(initial, 75e16);
    assertEq(riskFreeRate, 20e16);
  }

  function testInvalidParamSetting() public {
    IPCRM.SpotShockParams memory validSpotShocks = IPCRM.SpotShockParams({
      upInitial: 120e16,
      downInitial: 80e16,
      upMaintenance: 110e16,
      downMaintenance: 90e16,
      timeSlope: 1e18
    });

    IPCRM.VolShockParams memory validVolShocks = IPCRM.VolShockParams({
      minVol: 1e18,
      maxVol: 3e18,
      timeA: 30 days,
      timeB: 90 days,
      spotJumpMultipleSlope: 5e18,
      spotJumpMultipleLookback: 1 days
    });

    IPCRM.PortfolioDiscountParams memory validPortfolioParam = IPCRM.PortfolioDiscountParams({
      maintenance: 90e16, // 90%
      initial: 80e16, // 80%
      riskFreeRate: 10e16 // 10%
    });
  
    // invalid spot shocks
    validSpotShocks.upInitial = 0.8e18;
    vm.expectRevert(PCRM.PCRM_InvalidMarginParam.selector);
    manager.setParams(validSpotShocks, validVolShocks, validPortfolioParam);
    validSpotShocks.upInitial = 1.2e18;

    validSpotShocks.downInitial = 0.95e18;
    vm.expectRevert(PCRM.PCRM_InvalidMarginParam.selector);
    manager.setParams(validSpotShocks, validVolShocks, validPortfolioParam);
    validSpotShocks.downInitial = 0.8e18;

    // invalid vol shocks
    validVolShocks.timeA = block.timestamp + 10 days;
    validVolShocks.timeB = block.timestamp + 1 days;
    vm.expectRevert(PCRM.PCRM_InvalidMarginParam.selector);
    manager.setParams(validSpotShocks, validVolShocks, validPortfolioParam);
    validVolShocks.timeA = block.timestamp + 1 days;
    validVolShocks.timeB = block.timestamp + 10 days;

    validVolShocks.minVol = 150e18;
    validVolShocks.maxVol = 125e18;
    vm.expectRevert(PCRM.PCRM_InvalidMarginParam.selector);
    manager.setParams(validSpotShocks, validVolShocks, validPortfolioParam);
    validVolShocks.minVol = 150e18;
    validVolShocks.maxVol = 175e18;

    // invalid portfolio discount
    validPortfolioParam.initial = 1.1e18;
    vm.expectRevert(PCRM.PCRM_InvalidMarginParam.selector);
    manager.setParams(validSpotShocks, validVolShocks, validPortfolioParam);
  }

  function testSetNewSpotJumpOracle() public {
    uint oldMultiple = manager.getSpotJumpMultiple(1e18, 1 days);
    assertEq(oldMultiple, 1e18);

    // set new oracle
    MockSpotJumpOracle newSpotJumpOracle = new MockSpotJumpOracle();
    manager.setSpotJumpOracle(ISpotJumpOracle(address(newSpotJumpOracle)));
    newSpotJumpOracle.setMaxJump(4500);
    uint multiple = manager.getSpotJumpMultiple(1e18, 1 days);
    assertEq(multiple, 1.45e18);
    assertGt(multiple, oldMultiple);
  }
}