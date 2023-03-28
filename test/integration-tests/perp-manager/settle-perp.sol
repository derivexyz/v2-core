// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "../../shared/mocks/MockManager.sol";
import "../../shared/mocks/MockFeed.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../assets/cashAsset/mocks/MockInterestRateModel.sol";

import "src/Accounts.sol";
import "src/risk-managers/PerpManager.sol";
import "src/assets/PerpAsset.sol";
import "src/assets/CashAsset.sol";
import "src/interfaces/IAccounts.sol";
import "src/interfaces/IPerpAsset.sol";

/**
 * This test use the real PerpManager & PerpAsset to test the settlement flow
 */
contract INTEGRATION_PerpAssetSettlement is Test {
  PerpAsset perp;
  PerpManager manager;
  CashAsset cash;
  Accounts account;
  MockFeed feed;
  MockERC20 usdc;
  MockInterestRateModel rateModel;

  // keeper address to set impact prices
  address keeper = address(0xb0ba);
  // users
  address alice = address(0xaaaa);
  address bob = address(0xbbbb);
  address charlie = address(0xcccc);
  // accounts
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  int oneContract = 1e18;

  uint initPrice = 1500e18;

  function setUp() public {
    // deploy contracts
    account = new Accounts("Lyra", "LYRA");
    feed = new MockFeed();

    usdc = new MockERC20("USDC", "USDC");

    rateModel = new MockInterestRateModel(1e18);
    cash = new CashAsset(account, usdc, rateModel, 0, address(0));

    perp = new PerpAsset(IAccounts(account), feed);

    manager = new PerpManager(account, cash, perp, feed);

    cash.setWhitelistManager(address(manager), true);

    perp.setWhitelistManager(address(manager), true);
    perp.setImpactPriceOracle(keeper);

    // create account for alice, bob, charlie
    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = account.createAccountWithApproval(charlie, address(this), manager);

    _setPrices(initPrice);

    // open trades: Alice is Short, Bob is Long
    _tradePerpContract(aliceAcc, bobAcc, oneContract);
  }

  function testSettleLongPosition() public {
    int cashBefore = _getCashBalance(bobAcc);

    _setPrices(1600e18);

    // bobAcc close his position and has $100 in PNL
    _tradePerpContract(bobAcc, aliceAcc, oneContract);

    manager.settleAccount(bobAcc);

    int cashAfter = _getCashBalance(bobAcc);

    // bob has $100 in PNL
    assertEq(cashBefore + 100e18, cashAfter);
  }

  function testSettleShortPosition() public {
    int cashBefore = _getCashBalance(aliceAcc);

    // alice is short, bob is long
    _setPrices(1600e18);

    // alice close his position and has $100 in PNL
    _tradePerpContract(bobAcc, aliceAcc, oneContract);

    manager.settleAccount(aliceAcc);

    int cashAfter = _getCashBalance(aliceAcc);

    // alice has lost $100
    assertEq(cashBefore - 100e18, cashAfter);
  }

  /* -------------------------- */
  /* Test Long position on Bob  */
  /* -------------------------- */

  // function testIncreaseLongPosition() public {
  //   // price increase, in favor of Bob's position
  //   _setPrices(1600e18);

  //   // bob has $100 in unrealized PNL
  //   assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 100e18);

  //   // bob trade with charlie to increase long position
  //   _tradePerpContract(charlieAcc, bobAcc, oneContract);

  //   (uint entryPrice, int pnl) = _getEntryPriceAndPNL(bobAcc);
  //   assertEq(entryPrice, 1550e18);
  //   assertEq(pnl, 0);

  //   // still $100 in unrealized PNL
  //   assertEq(perp.getUnsettledAndUnrealizedCash(bobAcc), 100e18);
  // }

  function _setPrices(uint price) internal {
    feed.setSpot(price);
    vm.prank(keeper);
    perp.setImpactPrices(int(price), int(price));
  }

  function _getEntryPriceAndPNL(uint acc) internal view returns (uint, int) {
    (uint entryPrice,, int pnl,,) = perp.positions(acc);
    return (entryPrice, pnl);
  }

  function _tradePerpContract(uint fromAcc, uint toAcc, int amount) internal {
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: perp,
      subId: 0,
      amount: amount,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, cash, 0);
  }
}
