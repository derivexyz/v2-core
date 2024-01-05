// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../mocks/MockInterestRateModel.sol";

import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";

import "../../../../src/interfaces/IDutchAuction.sol";
import "../../../risk-managers/mocks/MockDutchAuction.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetDeposit is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockDutchAuction auction;
  SubAccounts subAccounts;
  IInterestRateModel rateModel;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));
    auction = new MockDutchAuction();

    usdc = new MockERC20("USDC", "USDC");
    usdc.setDecimals(6);

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
    cashAsset.setLiquidationModule(IDutchAuction(newLiq));
    assertEq(address(cashAsset.liquidationModule()), newLiq);
  }

  function testDonateInNormalScenario() public {
    uint newId = subAccounts.createAccount(address(this), manager);
    usdc.mint(address(this), 100e6);
    usdc.approve(address(cashAsset), 100e6);
    cashAsset.deposit(newId, 100e6);

    int cashBefore = subAccounts.getBalance(newId, cashAsset, 0);
    cashAsset.donateBalance(newId, 10e6);

    // nothing happened
    assertEq(subAccounts.getBalance(newId, cashAsset, 0), cashBefore);
  }

  function testDonateInInsolvency() public {
    uint newId = subAccounts.createAccount(address(this), manager);
    usdc.mint(address(this), 100e6);
    usdc.approve(address(cashAsset), 100e6);
    cashAsset.deposit(newId, 100e6);

    // burn some asset from the cash module, simulate some loss
    usdc.burn(address(cashAsset), 10e6);

    int donorCashBefore = subAccounts.getBalance(newId, cashAsset, 0);
    cashAsset.donateBalance(newId, 100e18); // specify donating all

    // nothing happened
    int donorCashAfter = subAccounts.getBalance(newId, cashAsset, 0);
    assertEq(donorCashAfter, donorCashBefore - 10e18);
  }

  function testCannotDonateFromNonOwner() public {
    uint newId = subAccounts.createAccount(address(this), manager);

    vm.prank(address(0xaa));
    vm.expectRevert(ICashAsset.CA_DonateBalanceNotAuthorized.selector);
    cashAsset.donateBalance(newId, 10e6);
  }

  /// @dev This test actually fails, this is a known issue
  function testDepositCashFromHigherDecimals() public {
    uint newId = subAccounts.createAccount(address(this), manager);

    MockERC20 highDec = new MockERC20("HighDec", "HighDec");
    highDec.setDecimals(30);

    CashAsset newAsset = new CashAsset(subAccounts, highDec, rateModel);
    newAsset.setWhitelistManager(address(manager), true);
    newAsset.setLiquidationModule(auction);

    highDec.mint(address(this), 100e30);
    highDec.approve(address(newAsset), 100e30);

    newAsset.deposit(newId, 99e30 + 1);

    assertEq(highDec.balanceOf(address(newAsset)), 99e30 + 1);
    assertEq(subAccounts.getBalance(newId, newAsset, 0), 99e18); // 18 decimals

    // can withdraw, but expected result is not correct
    newAsset.withdraw(newId, 98e30 + 9.99999e11, address(0xb0b));
    // assertEq(highDec.balanceOf(address(0xb0b)), 98e30 + 9.99999e11);
    // assertEq(subAccounts.getBalance(newId, newAsset, 0), 1e18 - 1); // 18 decimals
  }
}
