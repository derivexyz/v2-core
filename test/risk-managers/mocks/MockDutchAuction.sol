// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";

contract MockDutchAuction is IDutchAuction {
  bool blocking;

  function startAuction(uint accountId, uint scenarioId) external {}
  function startForcedAuction(uint accountId, uint scenarioId) external {}

  function getIsWithdrawBlocked() external view returns (bool) {
    return blocking;
  }

  function setMockBlockWithdraw(bool _blocking) external {
    blocking = _blocking;
  }
}
