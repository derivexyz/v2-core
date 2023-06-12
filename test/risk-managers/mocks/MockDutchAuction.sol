// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {IDutchAuction} from "src/interfaces/IDutchAuction.sol";

contract MockDutchAuction is IDutchAuction {
  function startAuction(uint accountId, uint scenarioId) external {}
  function startForcedAuction(uint accountId, uint scenarioId) external {}
}
