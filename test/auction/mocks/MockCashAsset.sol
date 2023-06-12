//SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import "openzeppelin/token/ERC20/IERC20.sol";
import "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";
import "lyra-utils/decimals/DecimalMath.sol";

import {ICashAsset} from "src/interfaces/ICashAsset.sol";
import {ISubAccounts} from "src/interfaces/ISubAccounts.sol";
import "../../shared/mocks/MockAsset.sol";

/**
 * @title MockCash
 */

contract MockCash is ICashAsset, MockAsset {
  using DecimalMath for uint;

  IERC20Metadata public wrappedAsset;

  bool public isSocialized;

  int public mockedBalanceWithInterest;

  uint public mockedExchangeRate;

  int public netSettledCash;

  constructor(IERC20 token_, ISubAccounts subAccounts_) MockAsset(token_, subAccounts_, true) {
    wrappedAsset = IERC20Metadata(address(token_));
  }

  function socializeLoss(uint lossAmountInCash, uint accountToReceive) external {
    isSocialized = true;
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
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

  function deposit(uint recipientAccount, uint stableAmount) external override(MockAsset, IERC20BasedAsset) {
    _deposit(recipientAccount, stableAmount);
  }

  function depositToNewAccount(address recipient, uint stableAmount, IManager manager)
    external
    returns (uint newAccountId)
  {
    newAccountId = subAccounts.createAccount(recipient, manager);
    _deposit(newAccountId, stableAmount);
  }

  function _deposit(uint recipientAccount, uint amount) internal {
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
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

  function withdraw(uint accountId, uint amount, address recipient) external override(MockAsset, IERC20BasedAsset) {
    subAccounts.assetAdjustment(
      ISubAccounts.AssetAdjustment({
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
