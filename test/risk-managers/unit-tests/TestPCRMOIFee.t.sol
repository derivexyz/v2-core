pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/Accounts.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeed.sol";

import "src/libraries/OptionEncoding.sol";

contract UNIT_TestPCRMOIFee is Test, AccountStructs {
  Accounts accounts;
  PCRM manager;
  MockAsset cash;
  MockERC20 usdc;

  MockFeed feed;
  MockOption option;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;
  uint feeRecipientAcc;

  function setUp() public {
    accounts = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    feed = new MockFeed();
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(accounts);
    cash = new MockAsset(usdc, accounts, true);

    manager = new PCRM(
      accounts,
      feed,
      feed,
      ICashAsset(address(cash)),
      option,
      address(0) // auction
    );

    manager.setParams(
      PCRM.Shocks({
        spotUpInitial: 120e16,
        spotDownInitial: 80e16,
        spotUpMaintenance: 110e16,
        spotDownMaintenance: 90e16,
        vol: 300e16,
        rfr: 10e16
      }),
      PCRM.Discounts({maintenanceStaticDiscount: 90e16, initialStaticDiscount: 80e16})
    );

    aliceAcc = accounts.createAccount(alice, IManager(manager));
    bobAcc = accounts.createAccount(bob, IManager(manager));

    vm.prank(alice);
    accounts.approve(address(this), aliceAcc);

    vm.prank(bob);
    accounts.approve(address(this), bobAcc);

    feeRecipientAcc = accounts.createAccount(address(this), IManager(manager));
    manager.setFeeRecipient(feeRecipientAcc);
  }

  function testCannotSetMaliciousFeeRecipient() public {
    vm.expectRevert("ERC721: invalid token ID");
    manager.setFeeRecipient(50);
  }

  function testAdminCanUpdateFeeRecipient() public {
    manager.setFeeRecipient(aliceAcc);
    assertEq(manager.feeRecipientAcc(), aliceAcc);
  }

  function testAdminCanUpdateOIFeeRate() public {
    manager.setOIFeeRateBPS(0.01e18);
    assertEq(manager.OIFeeRateBPS(), 0.01e18);
  }

  function testSubmitTransferChargeOIFee() public {
    _depositCash(alice, aliceAcc, 1000e18);
    _depositCash(bob, bobAcc, 1000e18);

    uint expiry = block.timestamp + 7 days;
    uint spotPrice = 1000e18;
    feed.setSpot(spotPrice);

    uint96 subId1 = OptionEncoding.toSubId(expiry, 1200e18, true);
    uint96 subId2 = OptionEncoding.toSubId(expiry, 1500e18, true);

    // mock OI tracking: OI increase for both subId1, ans subId2
    option.setMockedOI(subId1, 100e18);
    option.setMockedOI(subId2, 100e18);

    int aliceCashBefore = accounts.getBalance(aliceAcc, cash, 0);
    int bobCashBefore = accounts.getBalance(bobAcc, cash, 0);

    int amount = 10e18;
    int premium = 500e18;
    AccountStructs.AssetTransfer[] memory transferBatch = new AssetTransfer[](3);
    transferBatch[0] = AssetTransfer(aliceAcc, bobAcc, option, subId1, amount, bytes32(0));
    transferBatch[1] = AssetTransfer(aliceAcc, bobAcc, option, subId2, amount, bytes32(0));
    transferBatch[2] = AssetTransfer(bobAcc, aliceAcc, cash, 0, premium, bytes32(0));

    accounts.submitTransfers(transferBatch, "");

    int aliceCashAfter = accounts.getBalance(aliceAcc, cash, 0);
    int bobCashAfter = accounts.getBalance(bobAcc, cash, 0);

    // spotPrice(1000) * 0.1% * amount traded(20 in total)
    int expectedOIFee = 20e18;

    // alice ending balance = starting balance + premium - fee
    assertEq(aliceCashAfter, aliceCashBefore + premium - expectedOIFee);

    // bob ending balance = starting balance - premium - fee
    assertEq(bobCashAfter, bobCashBefore - premium - expectedOIFee);

    assertEq(accounts.getBalance(feeRecipientAcc, cash, 0), expectedOIFee * 2);
  }

  function _depositCash(address user, uint account, uint amount) internal {
    usdc.mint(user, amount);
    vm.startPrank(user);
    usdc.approve(address(cash), type(uint).max);
    cash.deposit(account, 0, amount);
    vm.stopPrank();
  }
}
