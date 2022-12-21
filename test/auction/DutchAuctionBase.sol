// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "../../src/Account.sol";
import "../shared/mocks/MockERC20.sol";
import "../shared/mocks/MockAsset.sol";

import "../../src/liquidation/DutchAuction.sol";

import "../shared/mocks/MockManager.sol";
import "../shared/mocks/MockFeed.sol";
import "../shared/mocks/MockIPCRM.sol";

contract DutchAuctionBase is Test {
  uint ownAcc;
  uint expiry;
  Account account;
  MockERC20 usdc;
  MockERC20 dai;
  MockAsset usdcAdapter;
  MockAsset optionAdapter;
  MockIPCRM manager;
  MockFeed feed;
  DutchAuction dutchAuction;

  function run() external {
    deployMockSystem();
    setupAccounts(500);
  }

  function setupAccounts(uint amount) public {
    // create 1 account for EOA
    ownAcc = account.createAccount(msg.sender, IManager(address(manager)));
    usdc.mint(msg.sender, 1000_000_000e18);
    usdc.approve(address(usdcAdapter), type(uint).max);
    usdcAdapter.deposit(ownAcc, 0, 100_000_000e18);
    // create bunch of accounts and send to everyone
    for (uint160 i = 1; i <= amount; i++) {
      address owner = address(i);
      uint acc = account.createAccountWithApproval(owner, msg.sender, IManager(address(manager)));

      // deposit usdc for each account
      usdcAdapter.deposit(acc, 0, 1_000e18);
    }

    expiry = block.timestamp + 1 days;
  }

  /// @dev deploy mock system
  function deployMockSystem() public {
    /* Base Layer */
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");

    // usdc asset: deposit with usdc, cannot be negative
    usdcAdapter = new MockAsset(IERC20(usdc), IAccount(address(account)), false);

    // optionAsset: not allow deposit, can be negative
    optionAdapter = new MockAsset(IERC20(address(0)), IAccount(address(account)), true);

    /* Risk Manager */
    manager = new MockIPCRM(address(account));

    /*
     Feed for Spot*/
    feed = new MockFeed();
    feed.setSpot(1e18 * 1000); // setting feed to 1000 usdc per eth

    dutchAuction = new DutchAuction(feed, manager);
  }
}
