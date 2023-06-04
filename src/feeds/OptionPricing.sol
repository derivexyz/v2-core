pragma solidity ^0.8.13;

import "lyra-utils/math/Black76.sol";
import "src/interfaces/IOptionPricing.sol";


contract OptionPricing is IOptionPricing {
  function getExpiryOptionsValue(Expiry memory expiryDetails, Option[] memory options) external pure returns (int) {
    int totalMTM;
    // TODO: maybe we wanna keep call/put price around in case we need it for next options
    for (uint i = 0; i < options.length; i++) {
      totalMTM += getOptionValue(expiryDetails, options[i]);
    }
    return totalMTM;
  }

  function getOptionValue(Expiry memory expiryDetails, Option memory option) public pure returns (int) {
    // console2.log all arguments
    (uint call, uint put) = Black76.prices(
      Black76.Black76Inputs({
        timeToExpirySec: expiryDetails.secToExpiry,
        volatility: option.vol,
        fwdPrice: expiryDetails.forwardPrice,
        strikePrice: option.strike,
        discount: expiryDetails.discountFactor
      })
    );

    return (option.isCall ? int(call) * option.amount : int(put) * option.amount) / 1e18;
  }
}
