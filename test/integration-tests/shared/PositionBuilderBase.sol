// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../shared/IntegrationTestBase.sol";
import "src/interfaces/IManager.sol";

/**
 * @dev a helper for building positions (e.g. leveraged boxes, zscs, etc.)
 */
contract PositionBuilderBase is IntegrationTestBase {
  struct Position {
    uint96 subId;
    int amount;
  }

  /**
   * @dev opens a max leveraged strategy
   * @param longAcc accId of whoever goes long the assets
   * @param shortAcc accId of whoever goes short the assets
   * @param positions array of Position (options only)
   */
  function _openStrategy(uint longAcc, uint shortAcc, Position[] memory positions) internal {
    // set up long and short accounts to hold max leveraged positions against one another

    _depositCash(address(accounts.ownerOf(longAcc)), longAcc, DEFAULT_DEPOSIT);
    _depositCash(address(accounts.ownerOf(shortAcc)), shortAcc, DEFAULT_DEPOSIT);

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

    cash.transferSmFees();

    int longMaxWithdraw = pcrm.getInitialMargin(pcrm.getPortfolio(longAcc));
    int shortMaxWithdraw = pcrm.getInitialMargin(pcrm.getPortfolio(shortAcc));

    _withdrawCash(address(accounts.ownerOf(longAcc)), longAcc, uint(longMaxWithdraw));
    _withdrawCash(address(accounts.ownerOf(shortAcc)), shortAcc, uint(shortMaxWithdraw));
  }

  /**
   * @dev opens a max leveraged ZSC (4 week expiry, 1 unit)
   */
  function _openLeveragedZSC(uint longAcc, uint shortAcc) internal returns (Position[] memory positions) {
    // set up long and short accounts to hold leveraged ZSCs against one another
    uint callId = option.getSubId(block.timestamp + 4 weeks, 0, true);
    positions = new Position[](1);
    positions[0] = Position({subId: uint96(callId), amount: 1e18});
    _openStrategy(longAcc, shortAcc, positions);
    return positions;
  }

  /**
   * @dev opens a max leveraged ATM forward (4 week expiry, 1 unit @ strike = spot)
   */
  function _openATMFwd(uint longAcc, uint shortAcc) internal returns (Position[] memory positions) {
    // set up long and short accounts to hold leveraged fwd against one another
    uint tte = 4 weeks;
    uint expiry = block.timestamp + tte;
    uint spot = feed.getFuturePrice(expiry);
    uint strike = spot;
    positions = new Position[](2);
    positions[0] = Position({subId: uint96(option.getSubId(expiry, strike, true)), amount: 1e18});
    positions[1] = Position({subId: uint96(option.getSubId(expiry, strike, false)), amount: -1e18});
    _openStrategy(longAcc, shortAcc, positions);
    return positions;
  }

  /**
   * @dev opens a max leveraged box (4 week expiry, 1 unit @ strike1 = spot and strike2 = spot + $100)
   */
  function _openBox(uint longAcc, uint shortAcc, uint notional) internal returns (Position[] memory positions) {
    // set up long and short accounts to hold leveraged box against one another
    uint expiry = block.timestamp + 4 weeks;
    uint strike1 = feed.getFuturePrice(expiry);
    uint strike2 = feed.getFuturePrice(expiry) + 100e18;
    int numBoxes = int(notional) * 1e18 / 100e18;
    positions = new Position[](4);
    positions[0] = Position({subId: uint96(option.getSubId(expiry, strike1, true)), amount: numBoxes});
    positions[1] = Position({subId: uint96(option.getSubId(expiry, strike1, false)), amount: -numBoxes});
    positions[2] = Position({subId: uint96(option.getSubId(expiry, strike2, true)), amount: -numBoxes});
    positions[3] = Position({subId: uint96(option.getSubId(expiry, strike2, false)), amount: numBoxes});
    _openStrategy(longAcc, shortAcc, positions);
    return positions;
  }
}
