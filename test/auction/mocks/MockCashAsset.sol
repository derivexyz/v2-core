//SPDX-License-Identifier:MIT
pragma solidity ^0.8.13;

import "openzeppelin/token/ERC20/IERC20.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IAccounts.sol";
import "../../shared/mocks/MockAsset.sol";
import "src/libraries/DecimalMath.sol";
/**
 * @title MockCash
 */

contract MockCash is ICashAsset, MockAsset {
  using DecimalMath for uint;

  bool public isSocialized;

  int public mockedBalanceWithInterest;

  uint public mockedExchangeRate;

  constructor(IERC20 token_, IAccounts accounts_) MockAsset(token_, accounts_, true) {}

  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external {
    isSocialized = true;
    account.assetAdjustment(
      AccountStructs.AssetAdjustment({
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
      AccountStructs.AssetAdjustment({
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
      AccountStructs.AssetAdjustment({
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

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function testSkip() public {}
}
