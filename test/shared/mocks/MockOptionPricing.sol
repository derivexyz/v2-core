pragma solidity ^0.8.13;

import "lyra-utils/decimals/DecimalMath.sol";

import "../../../src/interfaces/IOptionPricing.sol";

contract MockOptionPricing is IOptionPricing {
  using DecimalMath for uint;

  // mocked strike => expiry => mock value
  mapping(uint => mapping(uint => mapping(bool => uint))) public mockMTM;

  function getExpiryOptionsValue(Expiry memory expiryDetails, Option[] memory options)
    external
    view
    override
    returns (int)
  {
    int total = 0;
    for (uint i = 0; i < options.length; i++) {
      total += getOptionValue(expiryDetails, options[i]) * options[i].amount / 1e18;
    }
    return total;
  }

  function getOptionValue(Expiry memory expiryDetails, Option memory option) public view returns (int) {
    return
      int(mockMTM[option.strike][block.timestamp + expiryDetails.secToExpiry][option.isCall]) * option.amount / 1e18;
  }

  // set mock value
  function setMockMTM(uint strike, uint expiry, bool isCall, uint value) external {
    mockMTM[strike][expiry][isCall] = value;
  }
}
