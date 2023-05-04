pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "src/assets/Option.sol";
import "src/risk-managers/PCRM.sol";
import "src/Accounts.sol";

import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockAsset.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeed.sol";
import "test/risk-managers/mocks/MockSpotJumpOracle.sol";

contract UNIT_TestPCRMOIFee is Test {
  Accounts accounts;
  PCRM manager;
  MockAsset cash;
  MockERC20 usdc;

  MockFeed feed;
  MockSpotJumpOracle spotJumpOracle;
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
    spotJumpOracle = new MockSpotJumpOracle();

    manager = new PCRM(
      accounts,
      feed,
      feed,
      ICashAsset(address(cash)),
      option,
      address(0), // auction
      ISpotJumpOracle(address(spotJumpOracle))
    );

    manager.setParams(
      IPCRM.SpotShockParams({
        upInitial: 120e16,
        downInitial: 80e16,
        upMaintenance: 110e16,
        downMaintenance: 90e16,
        timeSlope: 1e18
      }),
      IPCRM.VolShockParams({
        minVol: 1e18,
        maxVol: 3e18,
        timeA: 30 days,
        timeB: 90 days,
        spotJumpMultipleSlope: 5e18,
        spotJumpMultipleLookback: 1 days
      }),
      IPCRM.PortfolioDiscountParams({
        maintenance: 90e16, // 90%
        initial: 80e16, // 80%
        initialStaticCashOffset: 0,
        riskFreeRate: 10e16 // 10%
      })
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
    _depositCash(bob, bobAcc, 3000e18);

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
    int premium = 2500e18;
    IAccounts.AssetTransfer[] memory transferBatch = new IAccounts.AssetTransfer[](3);
    transferBatch[0] = IAccounts.AssetTransfer(aliceAcc, bobAcc, option, subId1, amount, bytes32(0));
    transferBatch[1] = IAccounts.AssetTransfer(aliceAcc, bobAcc, option, subId2, amount, bytes32(0));
    transferBatch[2] = IAccounts.AssetTransfer(bobAcc, aliceAcc, cash, 0, premium, bytes32(0));

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
