// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IDutchAuction} from "../../../src/interfaces/IDutchAuction.sol";
import {ICashAsset} from "../../../src/interfaces/ICashAsset.sol";

contract MockDutchAuction is IDutchAuction {
  bool blocking;
  ICashAsset public cash;
  mapping(uint => bool) public isAuctionLive;

  function startAuction(uint accountId, uint) external {
    isAuctionLive[accountId] = true;
  }

  function startForcedAuction(uint accountId, uint) external {
    isAuctionLive[accountId] = true;
  }

  function endAuction(uint accountId) external {
    isAuctionLive[accountId] = false;
  }

  function getIsWithdrawBlocked() external view returns (bool) {
    return blocking;
  }

  function setMockBlockWithdraw(bool _blocking) external {
    blocking = _blocking;
  }
}
