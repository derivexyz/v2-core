pragma solidity ^0.8.13;

import "lyra-utils/decimals/DecimalMath.sol";

import "src/interfaces/IOptionPricing.sol";

contract MockOptionPricing is IOptionPricing {
  using DecimalMath for uint;

  // mocked strike => expiry => mock value
  mapping(uint => mapping(uint => uint)) public mockMTM;

  function getMTM(uint strike, uint expiry, bool /*isCall*/ ) external view override returns (uint) {
    return mockMTM[strike][expiry];
  }

  // set mock value
  function setMockMTM(uint strike, uint expiry, uint value) external {
    mockMTM[strike][expiry] = value;
  }
}
