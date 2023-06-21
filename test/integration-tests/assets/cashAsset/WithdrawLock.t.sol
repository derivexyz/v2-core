// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";

import "../../shared/IntegrationTestBase.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract INTEGRATION_BorrowAgainstOptionsTest is IntegrationTestBase {
  using DecimalMath for uint;

  uint64 expiry;
  IOption option;

  function setUp() public {
    _setupIntegrationTestComplete();

    option = markets["weth"].option;

    // Alice and Bob deposit cash into the system
    _depositCash(address(alice), aliceAcc, 2000e18);
    _depositCash(address(bob), bobAcc, 2000e18);

    expiry = uint64(block.timestamp + 1 weeks);
    // set forward price for expiry
    _setForwardPrice("weth", expiry, 2000e18, 1e18);
    _setDefaultSVIForExpiry("weth", expiry);

    auction.setWithdrawBlockThreshold(-100e18);
  }

  function testBigInsolventAuctionLockWithdraw() public {
    // trade 2000 call
    _tradeCall(2000e18);

    _setSpotPrice("weth", 4000e18, 1e18);
    _setForwardPrice("weth", expiry, 4000e18, 1e18);

    // alice is ultra insolvent
    auction.startAuction(aliceAcc, 1);

    // bob cannot withdraw cash
    vm.prank(bob);
    vm.expectRevert(ICashAsset.CA_WithdrawBlockedByOngoingAuction.selector);
    cash.withdraw(bobAcc, 100e6, bob);
  }

  function testCanRecoverFromLock() public {
    // trade 2000 call
    _tradeCall(2000e18);

    _setSpotPrice("weth", 4000e18, 1e18);
    _setForwardPrice("weth", expiry, 4000e18, 1e18);

    // alice is ultra insolvent
    auction.startAuction(aliceAcc, 1);

    // bob can unlock by bidding the whole portfolio him self from a new acc ;)
    uint newAcc = subAccounts.createAccount(bob, srm);
    _depositCash(address(bob), newAcc, 2000e18);

    vm.startPrank(bob);
    auction.bid(aliceAcc, newAcc, 1e18);

    uint usdcBefore = usdc.balanceOf(bob);
    cash.withdraw(bobAcc, 100e6, bob);
    uint usdcAfter = usdc.balanceOf(bob);
    assertEq(usdcAfter, usdcBefore + 100e6);
  }

  function _tradeCall(uint strike) public {
    uint96 callId = getSubId(expiry, strike, true);
    _submitTrade(aliceAcc, option, callId, 1e18, bobAcc, cash, 0, 0);
  }
}
