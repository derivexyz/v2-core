pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "src/feeds/SFPSpotFeed.sol";
import "./sfp-contracts/StrandsAPI.sol";
import "./sfp-contracts/StrandsSFP.sol";
import {
  IntegrationTestBase,
  IStandardManager,
  Config,
  WrappedERC20Asset,
  IForwardFeed,
  IVolFeed,
  ISpotFeed,
  IManager,
  IBaseManager
} from "../../integration-tests/shared/IntegrationTestBase.t.sol";

contract SFPTest is IntegrationTestBase {
  address deployer;

  StrandsAPI strandsAPI;
  StrandsSFP strandsSFP;
  SFPSpotFeed sfpSpotFeed;

  WrappedERC20Asset wrappedSFP;

  function setUp() public {
    _setupIntegrationTestComplete();

    strandsAPI = new StrandsAPI(address(this), address(this));
    strandsSFP = new StrandsSFP(strandsAPI);
    sfpSpotFeed = new SFPSpotFeed(IStrandsSFP(address(strandsSFP)));

    wrappedSFP = new WrappedERC20Asset(subAccounts, IERC20Metadata(strandsSFP));

    wrappedSFP.setWhitelistManager(address(srm), true);
    wrappedSFP.setTotalPositionCap(srm, 1000e18);

    uint marketId = srm.createMarket("SFP");

    srm.whitelistAsset(wrappedSFP, marketId, IStandardManager.AssetType.Base);
    srm.setOraclesForMarket(marketId, ISpotFeed(sfpSpotFeed), IForwardFeed(address(0)), IVolFeed(address(0)));

    (,,, IStandardManager.BaseMarginParams memory baseMarginParams) = Config.getSRMParams();

    srm.setBaseAssetMarginFactor(marketId, 0.95e18, 0.9475e18);
    srm.setBorrowingEnabled(true);

    // setup accounts so some cash exists to borrow
    _setupAliceAndBob();
    _depositCash(bob, bobAcc, 10000e18);
  }

  function test_sfpSpotFeed() public {
    _mintSFP(alice, 100e18);

    assertEq(strandsSFP.balanceOf(alice), 100e18);
    assertEq(strandsSFP.totalSupply(), 100e18);
    (uint spot, uint confidence) = sfpSpotFeed.getSpot();
    assertEq(spot, 1e18);
    assertEq(confidence, 1e18);

    strandsAPI.mint(address(strandsSFP), 1e18);

    (spot, confidence) = sfpSpotFeed.getSpot();
    assertApproxEqAbs(spot, 1.01e18, 0.00001e18);
    assertEq(confidence, 1e18);
  }

  function test_borrowingAgainstSFP() public {
    _mintSFP(alice, 100e18);
    vm.startPrank(alice);
    uint subAcc = subAccounts.createAccount(alice, srm);
    strandsSFP.approve(address(wrappedSFP), 100e18);
    wrappedSFP.deposit(subAcc, 100e18);

    // 6 decimals for USDC
    cash.withdraw(subAcc, 50e6, alice);
    vm.stopPrank();
    assertEq(usdc.balanceOf(alice), 50e6);
  }

  function _mintSFP(address user, uint amount) internal {
    strandsAPI.mint(user, amount);
    vm.startPrank(user);
    strandsAPI.approve(address(strandsSFP), amount);
    strandsSFP.deposit(amount, user);
    vm.stopPrank();
  }

  function test_upperSfpPriceBoundHit() public {
    // Test if the upper price bound of SFPs is hit. Expect a revert
    _mintSFP(alice, 100e18);
    assertEq(strandsSFP.balanceOf(alice), 100e18);
    assertEq(strandsSFP.totalSupply(), 100e18);
    (uint spot, uint confidence) = sfpSpotFeed.getSpot();
    assertEq(spot, 1e18);
    assertEq(confidence, 1e18);
    strandsAPI.mint(address(strandsSFP), 40e18);
    vm.expectRevert(SFPSpotFeed.LSSSF_InvalidPrice.selector);
    (spot, confidence) = sfpSpotFeed.getSpot();
  }

  function test_lowerSfpPriceBoundHit() public {
    // As above but for hitting the lower bound
    sfpSpotFeed.setPriceBounds(1.1e18, 1.2e18); // Set lower bound > 1
    _mintSFP(alice, 100e18);
    assertEq(strandsSFP.balanceOf(alice), 100e18);
    assertEq(strandsSFP.totalSupply(), 100e18);
    vm.expectRevert(SFPSpotFeed.LSSSF_InvalidPrice.selector);
    (uint spot, uint confidence) = sfpSpotFeed.getSpot();
  }

  function test_positionCapHit() public {
    _mintSFP(alice, 1200e18);
    vm.startPrank(alice);
    uint subAcc = subAccounts.createAccount(alice, srm);
    strandsSFP.approve(address(wrappedSFP), 1200e18);
    vm.expectRevert(IBaseManager.BM_AssetCapExceeded.selector);
    wrappedSFP.deposit(subAcc, 1200e18);
  }

  function test_invalidSfpPriceBounds() public {
    vm.expectRevert(SFPSpotFeed.LSSSF_InvalidPriceBounds.selector);
    sfpSpotFeed.setPriceBounds(1.5e18, 1.2e18); // Set lower bound > upper bound
  }
}
