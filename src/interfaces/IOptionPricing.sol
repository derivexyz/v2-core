// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title IOptionPricing
 * @dev this module abstract away reading oracle data.
 *      We should be able to get reliable vol, future price ...etc from the oracle in the contract,
 *      and feed them into BlackScholes or Black76 model to get option price.
 * @notice Interface for option pricing
 */
interface IOptionPricing {
  function getMTM(uint strike, uint expiry, uint amount, bool isCall) external view returns (uint);
}
