// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lyra-utils/math/Black76.sol";

contract MTMCache {
  function getMTM(uint strike, uint expiry, uint forwardPrice, uint vol, uint discount, int amount, bool isCall)
    public
    view
    returns (int)
  {
    // console2.log all arguments
    (uint call, uint put) = Black76.prices(
      Black76.Black76Inputs({
        timeToExpirySec: uint64(expiry - block.timestamp),
        volatility: uint128(vol),
        fwdPrice: uint128(forwardPrice),
        strikePrice: uint128(strike),
        discount: uint64(discount)
      })
    );

    return (isCall ? int(call) * amount : int(put) * amount) / 1e18;
  }
}
