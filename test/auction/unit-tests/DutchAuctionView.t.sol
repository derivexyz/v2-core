// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DutchAuctionBase.sol";

contract UNIT_DutchAuctionView is DutchAuctionBase {
  function testSolventAuctionParams() public {
    // change params
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 0.98e18,
        fastAuctionCutoffPercentage: 0.8e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        liquidatorFeeRate: 0.05e18
      })
    );

    // check if params changed
    (
      uint64 startingMtMPercentage,
      uint64 cutoff,
      uint32 fastAuctionLength,
      uint32 slowAuctionLength,
      uint64 liquidatorFeeRate
    ) = dutchAuction.solventAuctionParams();
    assertEq(startingMtMPercentage, 0.98e18);
    assertEq(cutoff, 0.8e18);
    assertEq(fastAuctionLength, 300);
    assertEq(slowAuctionLength, 3600);
    assertEq(liquidatorFeeRate, 0.05e18);
  }

  function testCannotSetInvalidParams() public {
    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 1.02e18,
        fastAuctionCutoffPercentage: 0.8e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        liquidatorFeeRate: 0.05e18
      })
    );

    vm.expectRevert(IDutchAuction.DA_InvalidParameter.selector);
    dutchAuction.setSolventAuctionParams(
      IDutchAuction.SolventAuctionParams({
        startingMtMPercentage: 0.9e18,
        fastAuctionCutoffPercentage: 0.91e18,
        fastAuctionLength: 300,
        slowAuctionLength: 3600,
        liquidatorFeeRate: 0.05e18
      })
    );
  }

  function testSetInsolventAuctionParameters() public {
    dutchAuction.setInsolventAuctionParams(IDutchAuction.InsolventAuctionParams({totalSteps: 100, coolDown: 2}));

    // expect value
    (uint32 totalSteps, uint32 coolDown) = dutchAuction.insolventAuctionParams();
    assertEq(totalSteps, 100);
    assertEq(coolDown, 2);
  }

  function testGetDiscountPercentage() public {
    // default setting: fast auction 100% - 80% (600second), slow auction 80% - 0% (7200 secs)

    // auction starts!
    uint startTime = block.timestamp;

    // fast forward 300 seconds
    vm.warp(block.timestamp + 300);

    (uint discount, bool isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.9e18);
    assertTrue(isFast);

    // fast forward 300 seconds, 600 seconds into the auction
    vm.warp(block.timestamp + 300);
    (discount, isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.8e18);
    assertTrue(!isFast);

    // fast forward 360 seconds, 960 seconds into the auction
    vm.warp(block.timestamp + 360);
    (discount, isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.76e18);
    assertTrue(!isFast);

    // fast forward 7200 seconds, everything ends
    vm.warp(block.timestamp + 7200);
    (discount, isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0);
    assertTrue(!isFast);
  }

  function testGetDiscountPercentage2() public {
    // new setting: fast auction 96% - 80%, slow auction 80% - 0%
    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();
    params.startingMtMPercentage = 0.96e18;
    params.fastAuctionCutoffPercentage = 0.8e18;
    params.fastAuctionLength = 300;

    dutchAuction.setSolventAuctionParams(params);

    // auction starts!
    uint startTime = block.timestamp;

    (uint discount, bool isFast) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.96e18);
    assertTrue(isFast);

    // fast forward 150 seconds, half of fast auction
    vm.warp(block.timestamp + 150);
    (discount,) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.88e18);

    // another 150 seconds
    vm.warp(block.timestamp + 150);
    (discount,) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.8e18);

    // pass 90% of slow auction
    vm.warp(block.timestamp + 6480);
    (discount,) = dutchAuction.getDiscountPercentage(startTime, block.timestamp);
    assertEq(discount, 0.08e18);
  }
}
