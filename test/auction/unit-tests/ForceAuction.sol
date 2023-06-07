// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "./DutchAuctionBase.sol";

contract UNIT_TestForceAuction is DutchAuctionBase {
  function testCanStartForceAuction() public {
    vm.prank(address(manager));

    dutchAuction.startForcedAuction(aliceAcc, 1);
  }

  function testCannotStartFromNonManager() public {
    vm.expectRevert(IDutchAuction.DA_OnlyManager.selector);
    vm.prank(address(0xbb));
    dutchAuction.startForcedAuction(aliceAcc, 1);
  }

  function testForceAuctionTakesNoFee() public {
    // enable fees
    IDutchAuction.SolventAuctionParams memory params = _getDefaultSolventParams();
    params.liquidatorFeeRate = 0.1e18;
    dutchAuction.setSolventAuctionParams(params);

    // mock mtm > 0
    manager.setMarkToMarket(aliceAcc, 100e18);

    vm.prank(address(manager));
    dutchAuction.startForcedAuction(aliceAcc, 1);

    // assert no fee charged
    int fee = subAccounts.getBalance(sm.accountId(), usdcAsset, 0);
    assertEq(fee, 0);
  }
}
