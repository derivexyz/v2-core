// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "synthetix/Owned.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/ICashAsset.sol";
import "../../shared/mocks/MockAsset.sol";

/**
 * @title Cash asset with built-in lending feature.
 * @dev   Users can deposit USDC and credit this cash asset into their accounts.
 *        Users can borrow cash by having a negative balance in their account (if allowed by manager).
 * @author Lyra
 */
contract MockCashAssetWithExchangeRate is MockAsset {
  mapping(uint => int) public mockedBalanceWithInterest;

  uint public mockExchangeRate = 1e18;

  constructor(IAccounts _accounts, IERC20Metadata _stableAsset) MockAsset(_stableAsset, _accounts, true) {}

  function calculateBalanceWithInterest(uint accountId) external view returns (int balance) {
    return mockedBalanceWithInterest[accountId];
  }

  function setAccBalanceWithInterest(uint acc, int balance) external {
    mockedBalanceWithInterest[acc] = balance;
  }

  function getCashToStableExchangeRate() external view returns (uint) {
    return mockExchangeRate;
  }

  function setMockedExchangeRate(uint rate) external {
    mockExchangeRate = rate;
  }

  function testMock() public {}
}
