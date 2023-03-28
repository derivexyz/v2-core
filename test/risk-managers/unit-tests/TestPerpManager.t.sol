pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/PerpManager.sol";

import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockFeed.sol";

contract UNIT_TestPerpManager is Test {
  Accounts account;
  PerpManager manager;
  MockAsset cash;
  MockERC20 usdc;
  MockPerp perp;

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

    feed = new MockFeed();

    manager = new PerpManager(
      account,
      ICashAsset(address(cash)),
      perp,
      feed
    );

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);
  }

  // ////////////////////
  // // Manager Change //
  // ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));

    // first fails the change
    vm.startPrank(alice);
    vm.expectRevert(IPerpManager.PM_NotWhitelistManager.selector);
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();

    manager.setWhitelistManager(address(newManager), true);
    vm.startPrank(alice);
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();
  }
}
