// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../mocks/MockInterestRateModel.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetDeposit is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  SubAccounts subAccounts;
  IInterestRateModel rateModel;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));

    usdc = new MockERC20("USDC", "USDC");

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(subAccounts, usdc, rateModel);

    cashAsset.setWhitelistManager(address(manager), true);
  }

  function testCanUpdateFeeRecipient() public {
    uint newId = subAccounts.createAccount(address(this), manager);
    cashAsset.setSmFeeRecipient(newId);
    assertEq(cashAsset.smId(), newId);
  }

  function testCanSetLiquidationModule() public {
    address newLiq = address(0x1111);
    cashAsset.setLiquidationModule(newLiq);
    assertEq(cashAsset.liquidationModule(), newLiq);
  }
}
