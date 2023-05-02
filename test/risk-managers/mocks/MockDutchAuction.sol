// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "src/interfaces/IDutchAuction.sol";

contract MockDutchAuction is IDutchAuction {
  function startAuction(uint accountId) external {}
}
