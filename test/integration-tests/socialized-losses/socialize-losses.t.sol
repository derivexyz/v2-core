// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";
import {IManager} from "src/interfaces/IManager.sol";

/**
 * @dev insolvent auction leads to socialize losses
 */
contract INTEGRATION_SocializeLosses is IntegrationTestBase {
  address charlie = address(0xcc);
  uint charlieAcc;

  // value used for test
  uint initSMFund = 100e18;

  int constant amountOfContracts = 10e18;
  uint constant strike = 2000e18;

  uint96 callId;

  // expiry = 7 days
  uint expiry;

  function setUp() public {
    _setupIntegrationTestComplete();

    // init setup for both accounts
    _depositCash(alice, aliceAcc, 8_000e18);
    _depositCash(bob, bobAcc, 10_000e18);

    charlieAcc = subAccounts.createAccount(charlie, IManager(address(srm)));
    _depositCash(charlie, charlieAcc, 10_000e18);

    expiry = block.timestamp + 14 days;
    callId = OptionEncoding.toSubId(expiry, strike, true);

    _setDefaultFeedValues();

    // alice will be slightly above init margin ($50)
    _openPosition();

    // charlie deposits into security module
    _depositCash(charlie, smAcc, initSMFund);
  }

  // whole flow from being insolvent => no enough fund in sm => socialized losses
  function testSocializeLosses() public {
    // price went up 100%, now alice is mega insolvent
    _setSpotPrice("weth", 5000e18, 1e18);

    _setDefaultFeedValues();
    (int im, int mm, int mtm) = _getMargins();

    console2.log("\ninit margin", im);
    console2.log("maintenance margin", mm);
    console2.log("mtm", mtm);

    assertLt(im, 0);
    assertLt(mm, 0);
    assertGt(mtm, 0);

    console2.log("start auction");
    // start auction on alice's account
    auction.startAuction(aliceAcc, 0);

    (im, mm, mtm) = _getMargins();

    console2.log("\ninit margin", im);
    console2.log("maintenance margin", mm);
    console2.log("mtm", mtm);

    vm.warp(
      block.timestamp + _getDefaultAuctionParams().fastAuctionLength + _getDefaultAuctionParams().slowAuctionLength + 1
    );
    _setDefaultFeedValues();

    (im, mm, mtm) = _getMargins();

    console2.log("\ninit margin", im);
    console2.log("maintenance margin", mm);
    console2.log("mtm", mtm);

    auction.convertToInsolventAuction(aliceAcc);
    vm.warp(block.timestamp + _getDefaultAuctionParams().insolventAuctionLength);
    _setDefaultFeedValues();

    // uint supplyBefore = cash.totalSupply();

    int bidPrice = auction.getCurrentBidPrice(aliceAcc);
    assertEq(bidPrice / 1e18, -256); // bidding now will require security module to pay out -256

    // bid from bob
    vm.prank(charlie);
    auction.bid(aliceAcc, charlieAcc, 1e18, 0, 0);

    // uint supplyAfter = cash.totalSupply();

    // now all positions are closed
    assertEq(getCashBalance(aliceAcc), 0);

    // withdraw fee enabled
    assertEq(cash.temporaryWithdrawFeeEnabled(), true);

    uint socializedExchangeRate = cash.getCashToStableExchangeRate();
    assertLt(socializedExchangeRate, 1e18); // < 1, around 0.79

    uint usdcBefore = usdc.balanceOf(bob);
    console2.log("usdc before", usdcBefore);
    int cashBefore = getCashBalance(bobAcc);

    // to withdraw 1000 USDC, now you burn way more cash
    _withdrawCash(bob, bobAcc, 1000e18);

    uint usdcAfter = usdc.balanceOf(bob);
    console2.log("usdc after", usdcAfter);
    int cashAfter = getCashBalance(bobAcc);

    // successfully withdraw 1000 USDC
    assertEq((usdcAfter - usdcBefore), 1000e6);
    assertEq((cashBefore - cashAfter), int(1000e18 * 1e18 / socializedExchangeRate));
    // assertEq((cashBefore - cashAfter), 1257_300000001245745883); // 1257 cash burned
  }

  function _setDefaultFeedValues() internal {
    _setSpotPrice("weth", 5000e18, 1e18);
    _setForwardPrice("weth", uint64(expiry), 2000e18, 1e18);
    _setDefaultSVIForExpiry("weth", uint64(expiry));
  }

  ///@dev alice go short, bob go long
  function _openPosition() public {
    int premium = 350e18 * 10; // 10 calls
    // alice send call to bob, bob send premium to alice
    _submitTrade(aliceAcc, markets["weth"].option, callId, amountOfContracts, bobAcc, cash, 0, premium);
  }

  function _getMargins() internal view returns (int, int, int) {
    return (getAccInitMargin(aliceAcc), getAccMaintenanceMargin(aliceAcc), getAccMtm(aliceAcc));
  }
}
