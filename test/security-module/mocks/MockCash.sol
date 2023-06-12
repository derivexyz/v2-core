// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin/utils/math/SafeCast.sol";
import "openzeppelin/access/Ownable2Step.sol";

import {IAsset} from "src/interfaces/IAsset.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";
import "src/interfaces/ICashAsset.sol";
import "../../shared/mocks/MockAsset.sol";

/**
 * @title Cash asset with built-in lending feature.
 * @dev   Users can deposit USDC and credit this cash asset into theirsubAccounts.
 *        Users can borrow cash by having a negative balance in their account (if allowed by manager).
 * @author Lyra
 */
contract MockCashAssetWithExchangeRate is MockAsset {
  mapping(uint => int) public mockedBalanceWithInterest;
  IERC20Metadata public immutable wrappedAsset;
  uint public mockExchangeRate = 1e18;
  int public netSettledCash;

  constructor(ISubAccounts _subAccounts, IERC20Metadata _stableAsset) MockAsset(_stableAsset, _subAccounts, true) {
    wrappedAsset = _stableAsset;
  }

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

  function updateSettledCash(int amountCash) external {
    netSettledCash += amountCash;
  }

  function testMock() public {}
}
