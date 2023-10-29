// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/liquidation/DutchAuction.sol";

contract PublicDutchAuction is DutchAuction {
  constructor(ISubAccounts _subAccounts, ISecurityModule _securityModule, ICashAsset _cash)
    Ownable2Step()
    DutchAuction(_subAccounts, _securityModule, _cash)
  {}

  function getInsolventAuctionBidPrice(uint accountId, int maintenanceMargin, int markToMarket)
    public
    view
    returns (int)
  {
    return _getInsolventAuctionBidPrice(accountId, maintenanceMargin, markToMarket);
  }
}
