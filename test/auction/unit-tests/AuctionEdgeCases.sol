pragma solidity ^0.8.20;

import "./DutchAuctionBase.sol";
import "../mocks/PublicDutchAuction.sol";

contract TestAuctionEdgeCases is DutchAuctionBase {
  PublicDutchAuction publicAuction;

  function setUp() public override {
    DutchAuctionBase.setUp();

    publicAuction = new PublicDutchAuction(subAccounts, sm, usdcAsset);
    publicAuction.setAuctionParams(_getDefaultAuctionParams());
  }

  function testGetInsolventBidPriceEdgeCases() public {
    vm.expectRevert(IDutchAuction.DA_AuctionNotStarted.selector);
    publicAuction.getInsolventAuctionBidPrice(bobAcc, -1000e18, 0);

    _startDefaultInsolventAuction(bobAcc);
    // MM > 0 -> always returns 0
    int bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, 1000e18, 0);
    assertEq(bidPrice, 0);
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, 1000e18, -100e18);
    assertEq(bidPrice, 0);
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, 1000e18, 100e18);
    assertEq(bidPrice, 0);

    // MM < 0 -> always returns min(MTM, 0) as auction has only just started
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, -1000e18, 0);
    assertEq(bidPrice, 0);
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, -1000e18, 100e18);
    assertEq(bidPrice, 0);
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, -1000e18, -100e18);
    assertEq(bidPrice, -100e18);

    // if insolvent auction length is 0, always return MM
    IDutchAuction.AuctionParams memory params = _getDefaultAuctionParams();
    params.insolventAuctionLength = 0;
    publicAuction.setAuctionParams(params);
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, -1000e18, 0);
    assertEq(bidPrice, -1000e18);
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, -1000e18, 100e18);
    assertEq(bidPrice, -1000e18);
    bidPrice = publicAuction.getInsolventAuctionBidPrice(bobAcc, -1000e18, -100e18);
    assertEq(bidPrice, -1000e18);
  }

  function _startDefaultInsolventAuction(uint acc) internal {
    manager.setMockMargin(acc, false, 0, -300e18);
    publicAuction.startAuction(acc, 0);
  }
}
