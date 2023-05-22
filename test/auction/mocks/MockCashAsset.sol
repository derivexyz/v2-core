//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import "src/interfaces/ICashAsset.sol";
import {IAccounts} from "src/interfaces/IAccounts.sol";
import "../../shared/mocks/MockAsset.sol";

/**
 * @title MockCash
 */

contract MockCash is ICashAsset, MockAsset {
  using DecimalMath for uint;

  bool public isSocialized;

  int public mockedBalanceWithInterest;

  uint public mockedExchangeRate;

  int public netSettledCash;

  constructor(IERC20 token_, IAccounts accounts_) MockAsset(token_, accounts_, true) {}

  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external {
    isSocialized = true;
    account.assetAdjustment(
      IAccounts.AssetAdjustment({
        acc: accountToReceive,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(lossAmountInCash.multiplyDecimal(tokenToCashRate)),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
  }

  function deposit(uint recipientAccount, uint amount) external override(MockAsset, ICashAsset) {
    account.assetAdjustment(
      IAccounts.AssetAdjustment({
        acc: recipientAccount,
        asset: IAsset(address(this)),
        subId: 0,
        amount: int(amount.multiplyDecimal(tokenToCashRate)),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transferFrom(msg.sender, address(this), amount);
  }

  function withdraw(uint accountId, uint amount, address recipient) external override(MockAsset, ICashAsset) {
    account.assetAdjustment(
      IAccounts.AssetAdjustment({
        acc: accountId,
        asset: IAsset(address(this)),
        subId: 0,
        amount: -int(amount.divideDecimal(tokenToCashRate)),
        assetData: bytes32(0)
      }),
      false,
      ""
    );
    token.transfer(recipient, amount);
  }

  function calculateBalanceWithInterest(uint) external view returns (int balance) {
    return mockedBalanceWithInterest;
  }

  function setBalanceWithInterest(int balWithInterest) external {
    mockedBalanceWithInterest = balWithInterest;
  }

  function getCashToStableExchangeRate() external view returns (uint) {
    return mockedExchangeRate;
  }

  function setExchangeRate(uint rate) external {
    mockedExchangeRate = rate;
  }

  function updateSettledCash(int amountCash) external {
    netSettledCash += amountCash;
  }

  function forceWithdraw(uint accountId) external {}

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function testSkip() public {}
}
