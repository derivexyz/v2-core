pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/SimpleManager.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeed.sol";
import "test/shared/mocks/MockOptionPricing.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestSimpleManager_Option is Test {
  Accounts account;
  SimpleManager manager;
  MockAsset cash;
  MockERC20 usdc;
  MockPerp perp;
  MockOption option;
  MockOptionPricing pricing;

  MockFeed feed;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockAsset(usdc, account, true);

    perp = new MockPerp(account);

    option = new MockOption(account);

    feed = new MockFeed();

    pricing = new MockOptionPricing();

    manager = new SimpleManager(
      account,
      ICashAsset(address(cash)),
      option,
      perp,
      feed
    );

    manager.setPricingModule(pricing);

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    feed.setSpot(1500e18);

    usdc.mint(address(this), 100_000e18);
    usdc.approve(address(cash), type(uint).max);

    // set init perp trading parameters
    manager.setPerpMarginRequirements(0.05e18, 0.1e18);

    cash.deposit(aliceAcc, 10000e18);
    cash.deposit(bobAcc, 10000e18);
  }

  //////////////////////////////////
  // Isolated Margin Calculations //
  //////////////////////////////////

  function testGetIsolatedMarginLongOTMCall() public {
    // long option result in 0 margin (no borrowing power)
    uint expiry = block.timestamp + 91 days;

    uint strike = 2000e18;

    pricing.setMockMTM(strike, expiry, true, 1.65e18);

    // margin of shorting 1 call
    int margin = manager.getIsolatedMargin(strike, expiry, 1e18, 1e18, false);

    assertEq(margin, 0);
  }

  function testGetIsolatedMarginLongITMCall() public {
    uint expiry = block.timestamp + 91 days;

    uint strike = 1000e18;
    pricing.setMockMTM(strike, expiry, true, 500.08e18);

    // long 1 call
    int margin = manager.getIsolatedMargin(strike, expiry, 1e18, 0, false);
    assertEq(margin, 0); 
  }

  function testGetIsolatedMarginShortATMCall() public {
    uint expiry = block.timestamp + 91 days;

    uint strike = 400e18;

    pricing.setMockMTM(strike, expiry, true, 1100e18);

    // margin of shorting 1 call
    int margin = manager.getIsolatedMargin(strike, expiry, -1e18, 0, false);

    console2.log("OTM call (IM)", margin);

    console2.log("OTM call (MM)", manager.getIsolatedMargin(strike, expiry, -1e18, 0, true));

    // assertEq(margin, 0); // -801.65
  }

  ////////////////////////////////
  //  Margin Checks for Options //
  ////////////////////////////////

  function testCanTradeOptionWithEnoughMargin() public {
    uint expiry = block.timestamp + 7 days;

    uint strike = 2000e18;

    pricing.setMockMTM(strike, expiry, true, 1.65e18);

    // alice short 1 2000-ETH CALL.
    _tradeOption(aliceAcc, bobAcc, 1e18, expiry, strike, true);
  }

  function _tradeOption(uint fromAcc, uint toAcc, int amount, uint expiry, uint strike, bool isCall) internal {
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, cash, 0);
  }
}
