// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../shared/IntegrationTestBase.t.sol";

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
  function _openStrategy(string memory key, uint longAcc, uint shortAcc, Position[] memory positions) internal {
    // set up long and short accounts to hold max leveraged positions against one another

    _depositCash(address(subAccounts.ownerOf(longAcc)), longAcc, DEFAULT_DEPOSIT);
    _depositCash(address(subAccounts.ownerOf(shortAcc)), shortAcc, DEFAULT_DEPOSIT);

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](positions.length);

    for (uint i = 0; i < positions.length; i++) {
      transferBatch[i] = ISubAccounts.AssetTransfer({
        fromAcc: shortAcc,
        toAcc: longAcc,
        asset: markets[key].option,
        subId: uint96(positions[i].subId),
        amount: positions[i].amount,
        assetData: bytes32(0)
      });
    }
    subAccounts.submitTransfers(transferBatch, "");

    cash.transferSmFees();

    int longMaxWithdraw = -markets[key].pmrm.getMargin(longAcc, true);
    console2.log("longMaxWithdraw", longMaxWithdraw);
    int shortMaxWithdraw = -markets[key].pmrm.getMargin(shortAcc, true);
    console2.log("shortMaxWithdraw", shortMaxWithdraw);

    // _withdrawCash(address(subAccounts.ownerOf(longAcc)), longAcc, uint(longMaxWithdraw));
    // _withdrawCash(address(subAccounts.ownerOf(shortAcc)), shortAcc, uint(shortMaxWithdraw));
  }

  /**
   * @dev opens a max leveraged box (4 week expiry, 1 unit @ strike1 = spot and strike2 = spot + $100)
   */
  function _openBox(string memory key, uint expiry, uint longAcc, uint shortAcc, uint notional)
    internal
    returns (Position[] memory positions)
  {
    // set up long and short accounts to hold leveraged box against one another
    (uint strike1,) = _getForwardPrice(key, expiry);
    uint strike2 = strike1 + 100e18;
    int numBoxes = int(notional) * 1e18 / 100e18;
    positions = new Position[](4);
    positions[0] = Position({subId: getSubId(expiry, strike1, true), amount: numBoxes});
    positions[1] = Position({subId: getSubId(expiry, strike1, false), amount: -numBoxes});
    positions[2] = Position({subId: getSubId(expiry, strike2, true), amount: -numBoxes});
    positions[3] = Position({subId: getSubId(expiry, strike2, false), amount: numBoxes});
    _openStrategy(key, longAcc, shortAcc, positions);
    return positions;
  }
}
