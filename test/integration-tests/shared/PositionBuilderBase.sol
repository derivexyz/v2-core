// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev testing charge of OI fee in a real setting
 */
contract PositionBuilderBase is IntegrationTestBase {
  struct Position {
    uint96 subId;
    int amount;
  }

  function _openStrategy(uint longAcc, uint shortAcc, Position[] memory positions) internal {
    // set up long and short accounts to hold max leveraged positions against one another

    //console2.log("-----BEFORE DEPOSIT-----");
    //console2.log("long cash:", getCashBalance(longAcc)/1e18);
    //console2.log("short cash:", accounts.getBalance(shortAcc, IAsset(cash), 0)/1e18);
    //console2.log(usdc.balanceOf(address(cash)));

    _depositCash(address(accounts.ownerOf(longAcc)), longAcc, DEFAULT_DEPOSIT);
    _depositCash(address(accounts.ownerOf(shortAcc)), shortAcc, DEFAULT_DEPOSIT);

    //console2.log("-----AFTER DEPOSIT-----");
    //console2.log("long cash:", accounts.getBalance(longAcc, IAsset(cash), 0)/1e18);
    //console2.log("short cash:", accounts.getBalance(shortAcc, IAsset(cash), 0)/1e18);
    //console2.log(usdc.balanceOf(address(cash)));
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](positions.length);

    for (uint i = 0; i < positions.length; i++) {
      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: shortAcc,
        toAcc: longAcc,
        asset: option,
        subId: uint96(positions[i].subId),
        amount: positions[i].amount,
        assetData: bytes32(0)
      });
    }
    accounts.submitTransfers(transferBatch, "");

    //console2.log("SMfees:", cash.accruedSmFees());

    cash.transferSmFees();

    //console2.log("-----AFTER TRADE-----");
    //console2.log("long cash:", accounts.getBalance(longAcc, IAsset(cash), 0)/1e18);
    //console2.log("short cash:", accounts.getBalance(shortAcc, IAsset(cash), 0)/1e18);
    //console2.log("SM balance:", accounts.getBalance(smAcc, IAsset(cash), 0)/1e18);

    int longMaxWithdraw = pcrm.getInitialMargin(pcrm.getPortfolio(longAcc));
    int shortMaxWithdraw = pcrm.getInitialMargin(pcrm.getPortfolio(shortAcc));

    _withdrawCash(address(accounts.ownerOf(longAcc)), longAcc, uint(longMaxWithdraw));
    _withdrawCash(address(accounts.ownerOf(shortAcc)), shortAcc, uint(shortMaxWithdraw));

    //console2.log("-----AFTER WITHDRAW-----");
    //console2.log("long cash:", accounts.getBalance(longAcc, IAsset(cash), 0)/1e18);
    //console2.log("short cash:", accounts.getBalance(shortAcc, IAsset(cash), 0)/1e18);
    //console2.log("SM balance:", accounts.getBalance(smAcc, IAsset(cash), 0)/1e18);
  }

  function _openLeveragedZSC(uint longAcc, uint shortAcc) internal returns (Position[] memory positions) {
    // set up long and short accounts to hold leveraged ZSCs against one another
    uint callId = option.getSubId(block.timestamp + 4 weeks, 0, true);
    Position[] memory positions = new Position[](1);
    positions[0] = Position({subId: uint96(callId), amount: 1e18});
    _openStrategy(longAcc, shortAcc, positions);
    return positions;
  }

  function _openATMFwd(uint longAcc, uint shortAcc) internal returns (Position[] memory positions) {
    // set up long and short accounts to hold leveraged fwd against one another
    uint spot = feed.getSpot(feedId);
    uint tte = 4 weeks;
    uint expiry = block.timestamp + tte;
    uint strike = spot;
    positions = new Position[](2);
    positions[0] = Position({subId: uint96(option.getSubId(expiry, strike, true)), amount: 1e18});
    positions[1] = Position({subId: uint96(option.getSubId(expiry, strike, false)), amount: -1e18});
    _openStrategy(longAcc, shortAcc, positions);
    return positions;
  }

  function _openBox(uint longAcc, uint shortAcc) internal returns (Position[] memory positions) {
    // set up long and short accounts to hold leveraged box against one another
    uint strike1 = feed.getSpot(feedId);
    uint strike2 = feed.getSpot(feedId) + 100e18;
    uint expiry = block.timestamp + 4 weeks;
    positions = new Position[](4);
    positions[0] = Position({subId: uint96(option.getSubId(expiry, strike1, true)), amount: 1e18});
    positions[1] = Position({subId: uint96(option.getSubId(expiry, strike1, false)), amount: -1e18});
    positions[2] = Position({subId: uint96(option.getSubId(expiry, strike2, true)), amount: -1e18});
    positions[3] = Position({subId: uint96(option.getSubId(expiry, strike2, false)), amount: 1e18});
    _openStrategy(longAcc, shortAcc, positions);
    return positions;
  }
}
