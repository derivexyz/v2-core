pragma solidity ^0.8.13;

import "lyra-utils/math/Black76.sol";
import "forge-std/console2.sol";

contract MTMCache {
  function getMTM(
    uint128 strike,
    uint64 secToExpiry,
    uint128 forwardPrice,
    uint128 vol,
    uint64 discount,
    int amount,
    bool isCall
  ) public view returns (int) {
    // console2.log all arguments
    (uint call, uint put) = Black76.prices(
      Black76.Black76Inputs({
        timeToExpirySec: secToExpiry,
        volatility: vol,
        fwdPrice: forwardPrice,
        strikePrice: strike,
        discount: discount
      })
    );

    return (isCall ? int(call) * amount : int(put) * amount) / 1e18;
  }
}
