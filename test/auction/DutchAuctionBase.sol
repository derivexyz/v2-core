//// SPDX-License-Identifier: UNLICENSED
//pragma solidity ^0.8.18;
//
//import "forge-std/Test.sol";
//import "forge-std/Script.sol";
//
//import "../../src/Accounts.sol";
//import "../shared/mocks/MockERC20.sol";
//import "../shared/mocks/MockAsset.sol";
//import "../shared/mocks/MockSM.sol";
//import "./mocks/MockCashAsset.sol";
//import "../../src/liquidation/DutchAuction.sol";
//
//import "../shared/mocks/MockManager.sol";
//import "../shared/mocks/MockFeeds.sol";
//
//contract DutchAuctionBase is Test {
//  address alice;
//  address bob;
//  uint aliceAcc;
//  uint bobAcc;
//
//  Accounts account;
//  MockSM sm;
//  MockERC20 usdc;
//  MockCash usdcAsset;
//  MockAsset optionAsset;
//  MockManager manager;
//  MockFeeds feed;
//  DutchAuction dutchAuction;
//
//  /// @dev deploy mock system
//  function deployMockSystem() public {
//    /* Base Layer */
//    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");
//
//    /* Wrappers */
//    usdc = new MockERC20("usdc", "USDC");
//
//    // usdc asset: deposit with usdc, cannot be negative
//    usdcAsset = new MockCash(IERC20(usdc), account);
//
//    // optionAsset: not allow deposit, can be negative
//    optionAsset = new MockAsset(IERC20(address(0)), account, true);
//
//    /* Risk Manager */
//    manager = new MockManager(address(account));
//
//    // mock cash
//    sm = new MockSM(account, usdcAsset);
//    sm.createAccountForSM(manager);
//
//    /*
//     Feed for Spot*/
//    feed = new MockFeeds();
//    feed.setSpot(1e18 * 1000); // setting feed to 1000 usdc per eth
//
//    dutchAuction = dutchAuction = new DutchAuction(manager, account, sm, usdcAsset);
//  }
//
//  function mintAndDeposit(
//    address user,
//    uint accountId,
//    MockERC20 token,
//    MockAsset assetWrapper,
//    uint subId,
//    uint amount
//  ) public {
//    token.mint(user, amount);
//
//    vm.startPrank(user);
//    token.approve(address(assetWrapper), type(uint).max);
//    assetWrapper.deposit(accountId, subId, amount);
//    vm.stopPrank();
//  }
//
//  function setupAccounts() public {
//    alice = address(0xaa);
//    bob = address(0xbb);
//    usdc.approve(address(usdcAsset), type(uint).max);
//
//    aliceAcc = account.createAccount(alice, manager);
//    bobAcc = account.createAccount(bob, manager);
//  }
//
//  function test() external {}
//}
