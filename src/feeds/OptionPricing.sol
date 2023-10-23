// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "lyra-utils/math/Black76.sol";
import {IOptionPricing} from "../interfaces/IOptionPricing.sol";

/**
 * @title OptionPricing
 * @author Lyra
 * @notice Contract that calculates option value for a specific market. Can be extended in the future to add cache to safe gas ...etc
 * TODO (anton): purge
 */
contract OptionPricing is IOptionPricing {
  function getExpiryOptionsValue(Expiry memory expiryDetails, Option[] memory options) external pure returns (int) {
    int totalMTM;
    for (uint i = 0; i < options.length; i++) {
      totalMTM += getOptionValue(expiryDetails, options[i]);
    }
    return totalMTM;
  }

  function getOptionValue(Expiry memory expiryDetails, Option memory option) public pure returns (int) {
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
