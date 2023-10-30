// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DutchAuctionBase.sol";

contract UNIT_DutchAuctionView is DutchAuctionBase {
  function testAuctionParams() public {
    // change params
    dutchAuction.setAuctionParams(
      IDutchAuction.AuctionParams({
        startingMtMPercentage: 0.98e18,
        fastAuctionCutoffPercentage: 0.8e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        insolventAuctionLength: 10 minutes,
        liquidatorFeeRate: 0.05e18,
        bufferMarginPercentage: 0.1e18
      })
    );

    // check if params changed
    (
      uint startingMtMPercentage,
      uint cutoff,
      uint fastAuctionLength,
      uint slowAuctionLength,
      uint insolventAuctionLength,
      uint liquidatorFeeRate,
      uint bufferMarginPercentage
    ) = dutchAuction.auctionParams();
    assertEq(startingMtMPercentage, 0.98e18);
    assertEq(cutoff, 0.8e18);
    assertEq(fastAuctionLength, 300);
    assertEq(slowAuctionLength, 3600);
    assertEq(insolventAuctionLength, 600);
    assertEq(liquidatorFeeRate, 0.05e18);
    assertEq(bufferMarginPercentage, 0.1e18);
  }

  function testCannotSetInvalidParams() public {
    IDutchAuction.AuctionParams memory params = _getDefaultAuctionParams();

    params.startingMtMPercentage = 1.01e18;
    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setAuctionParams(params);

    params.startingMtMPercentage = 0.99e18;
    params.fastAuctionCutoffPercentage = 1e18;

    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setAuctionParams(params);

    params.fastAuctionCutoffPercentage = 0.99e18;
    params.liquidatorFeeRate = 0.11e18;

    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setAuctionParams(params);

    params.liquidatorFeeRate = 0.1e18;
    dutchAuction.setAuctionParams(params);

    params.bufferMarginPercentage = 4.1e18;
    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setAuctionParams(params);
  }

  function testSetSMAccount() public {
    dutchAuction.setSMAccount(0);
    assertEq(dutchAuction.smAccount(), 0);
    dutchAuction.setSMAccount(100000);
    assertEq(dutchAuction.smAccount(), 100000);
  }

  function testGetDiscountPercentage() public {
    // default setting: fast auction 100% - 80% (600second), slow auction 80% - 0% (7200 secs)

    // auction starts!
    uint startTime = block.timestamp;

    // fast forward 300 seconds
    vm.warp(block.timestamp + 300);

    uint discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.9e18);

    // fast forward 300 seconds, 600 seconds into the auction
    vm.warp(block.timestamp + 300);
    discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.8e18);

    // fast forward 360 seconds, 960 seconds into the auction
    vm.warp(block.timestamp + 360);
    discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.76e18);

    // fast forward 7200 seconds, everything ends
    vm.warp(block.timestamp + 7200);
    discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0);
  }

  function testGetDiscountPercentage2() public {
    // new setting: fast auction 96% - 80%, slow auction 80% - 0%
    IDutchAuction.AuctionParams memory params = _getDefaultAuctionParams();
    params.startingMtMPercentage = 0.96e18;
    params.fastAuctionCutoffPercentage = 0.8e18;
    params.fastAuctionLength = 300;

    dutchAuction.setAuctionParams(params);

    // auction starts!
    uint startTime = block.timestamp;

    uint discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.96e18);

    // fast forward 150 seconds, half of fast auction
    vm.warp(block.timestamp + 150);
    discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.88e18);

    // another 150 seconds
    vm.warp(block.timestamp + 150);
    discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.8e18);

    // pass 90% of slow auction
    vm.warp(block.timestamp + 6480);
    discount = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.08e18);
  }
}
