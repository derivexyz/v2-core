pragma solidity ^0.8.13;

import "lyra-utils/math/Black76.sol";
import "forge-std/console2.sol";
import "../interfaces/IMTMCache.sol";

contract MTMCache is IMTMCache {
  function getExpiryMTM(Expiry memory expiryDetails, Option[] memory options) external view returns (int) {
    int totalMTM;
    // TODO: maybe we wanna keep call/put price around in case we need it for next options
    for (uint i = 0; i < options.length; i++) {
      totalMTM += getMTM(
        options[i].strike,
        expiryDetails.secToExpiry,
        expiryDetails.forwardPrice,
        options[i].vol,
        expiryDetails.discountFactor,
        options[i].amount,
        options[i].isCall
      );
    }
    return totalMTM;
  }

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
