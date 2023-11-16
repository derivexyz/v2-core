// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../../shared/mocks/MockERC20.sol";
import "../../../shared/mocks/MockManager.sol";
import "../../../risk-managers/mocks/MockDutchAuction.sol";
import "../mocks/MockInterestRateModel.sol";
import "../../../../src/assets/CashAsset.sol";
import "../../../../src/SubAccounts.sol";

import {IManagerWhitelist} from "../../../../src/interfaces/IManagerWhitelist.sol";

/**
 * @dev we deploy actual Account contract in these tests to simplify verification process
 */
contract UNIT_CashAssetWithdraw is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  MockManager badManager;
  SubAccounts subAccounts;
  IInterestRateModel rateModel;
  MockDutchAuction auction;
  address badActor = address(0x0fac);

  uint accountId;
  uint depositedAmount;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));
    badManager = new MockManager(address(subAccounts));

    usdc = new MockERC20("USDC", "USDC");

    auction = new MockDutchAuction();

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(subAccounts, usdc, rateModel);

    cashAsset.setWhitelistManager(address(manager), true);
    cashAsset.setLiquidationModule(auction);

    // 10000 USDC with 18 decimals
    depositedAmount = 10000 ether;
    usdc.mint(address(this), depositedAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositedAmount);
  }

  function testCanWithdrawByAccountAmount() public {
    uint withdrawAmount = 100 ether;
    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(accountId, withdrawAmount, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, withdrawAmount);

    // cash balance updated in account
    int accBalance = subAccounts.getBalance(accountId, cashAsset, 0);
    assertEq(accBalance, int(depositedAmount - withdrawAmount));
  }

  function testCannotWithdrawFromOthersAccount() public {
    vm.prank(badActor);
    vm.expectRevert(ICashAsset.CA_OnlyAccountOwner.selector);
    cashAsset.withdraw(accountId, 100 ether, address(this));
  }

  function testCannotWithdrawIfLockedFromAuctionModule() public {
    auction.setMockBlockWithdraw(true);
    vm.expectRevert(ICashAsset.CA_WithdrawBlockedByOngoingAuction.selector);
    cashAsset.withdraw(accountId, 100 ether, address(this));
  }

  function testCannotWithdrawFromAccountNotControlledByTrustedManager() public {
    uint badAccount = subAccounts.createAccount(address(this), badManager);
    vm.expectRevert(IManagerWhitelist.MW_UnknownManager.selector);
    cashAsset.withdraw(badAccount, 100 ether, address(this));
  }

  function testBorrowIfManagerAllows() public {
    // user with an empty account (no cash balance) can withdraw USDC
    // essentially borrow from the cashAsset contract
    uint emptyAccount = subAccounts.createAccount(address(this), manager);

    uint amountToBorrow = 1000 ether;

    uint usdcBefore = usdc.balanceOf(address(this));
    cashAsset.withdraw(emptyAccount, amountToBorrow, address(this));
    uint usdcAfter = usdc.balanceOf(address(this));

    assertEq(usdcAfter - usdcBefore, amountToBorrow);

    int accBalance = subAccounts.getBalance(emptyAccount, cashAsset, 0);

    // todo: number might change based on interest
    assertEq(accBalance, -(int(amountToBorrow)));
  }

  function testForceWithdraw() public {
    // transfer the subAccount to someone else
    address alice = address(0xaa);
    subAccounts.transferFrom(address(this), alice, accountId);

    vm.prank(address(manager));
    cashAsset.forceWithdraw(accountId);

    assertEq(usdc.balanceOf(address(alice)), depositedAmount);
  }

  function testCannotForceWithdrawFromNonManager() public {
    vm.expectRevert(ICashAsset.CA_ForceWithdrawNotAuthorized.selector);
    cashAsset.forceWithdraw(accountId);
  }

  function testCannotForceWithdrawIfLockedFromAuctionModule() public {
    auction.setMockBlockWithdraw(true);
    vm.expectRevert(ICashAsset.CA_WithdrawBlockedByOngoingAuction.selector);
    vm.prank(address(manager));
    cashAsset.forceWithdraw(accountId);
  }

  function testCannotForceWithdrawNegativeBalance() public {
    address alice = address(0xaa);
    uint acc2 = subAccounts.createAccount(alice, manager);

    subAccounts.submitTransfer(
      ISubAccounts.AssetTransfer({
        fromAcc: accountId,
        toAcc: acc2,
        asset: IAsset(cashAsset),
        subId: 0,
        amount: int(depositedAmount * 2),
        assetData: bytes32(0)
      }),
      ""
    );

    vm.prank(address(manager));
    vm.expectRevert(ICashAsset.CA_ForceWithdrawNegativeBalance.selector);
    cashAsset.forceWithdraw(accountId);
  }
}

/**
 * @dev tests with mocked stable ERC20 with 20 decimals
 */
contract UNIT_CashAssetWithdrawLargeDecimals is Test {
  CashAsset cashAsset;
  MockERC20 usdc;
  MockManager manager;
  SubAccounts subAccounts;
  IInterestRateModel rateModel;
  MockDutchAuction auction;

  uint accountId;

  function setUp() public {
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    manager = new MockManager(address(subAccounts));

    usdc = new MockERC20("USDC", "USDC");

    auction = new MockDutchAuction();

    // usdc as 20 decimals
    usdc.setDecimals(20);

    rateModel = new MockInterestRateModel(1e18);
    cashAsset = new CashAsset(subAccounts, usdc, rateModel);

    cashAsset.setWhitelistManager(address(manager), true);
    cashAsset.setLiquidationModule(auction);

    // 10000 USDC with 20 decimals
    uint depositAmount = 10000 * 1e20;
    usdc.mint(address(this), depositAmount);
    usdc.approve(address(cashAsset), type(uint).max);

    accountId = subAccounts.createAccount(address(this), manager);

    cashAsset.deposit(accountId, depositAmount);
  }

  function testWithdrawDustWillUpdateAccountBalance() public {
    // amount (7 * 1e-20) should be round up to (1 * 1e-18) in our account
    uint amountToWithdraw = 7;

    int cashBalanceBefore = subAccounts.getBalance(accountId, cashAsset, 0);

    cashAsset.withdraw(accountId, amountToWithdraw, address(this));

    int cashBalanceAfter = subAccounts.getBalance(accountId, cashAsset, 0);

    // cash balance in account is deducted by 1 wei
    assertEq(cashBalanceBefore - cashBalanceAfter, 1);
  }
}
