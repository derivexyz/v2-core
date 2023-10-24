// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import "../../../src/SubAccounts.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockPerp.sol";
import "../../shared/mocks/MockSM.sol";
import "../../shared/mocks/MockCash.sol";
import "../mocks/MockLiquidatableManager.sol";
import "../../../src/liquidation/DutchAuction.sol";

import "test/shared/mocks/MockFeeds.sol";

contract DutchAuctionBase is Test {
  address alice;
  address bob;
  address charlie;
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;

  SubAccounts subAccounts;
  MockSM sm;
  MockERC20 usdc;
  MockCash usdcAsset;
  MockPerp perpAsset;
  MockAsset optionAsset;
  MockLiquidatableManager manager;
  DutchAuction dutchAuction;

  function setUp() public {
    _deployMockSystem();

    _setupAccounts();
    // bob is the main liquidator in our test: give him 20K cash
    _mintAndDepositCash(bobAcc, 20_000e18);

    dutchAuction = new DutchAuction(subAccounts, sm, usdcAsset);

    dutchAuction.setSolventAuctionParams(_getDefaultSolventParams());
    dutchAuction.setInsolventAuctionParams(_getDefaultInsolventParams());

    dutchAuction.setBufferMarginPercentage(0.1e18);
  }

  /// @dev deploy mock system
  function _deployMockSystem() public {
    /* Base Layer */
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");

    // usdc asset
    usdcAsset = new MockCash(usdc, subAccounts);

    // optionAsset: not allow deposit, can be negative
    optionAsset = new MockAsset(IERC20(address(0)), subAccounts, true);

    perpAsset = new MockPerp(subAccounts);

    /* Risk Manager */
    manager = new MockLiquidatableManager(address(subAccounts));

    // mock cash
    sm = new MockSM(subAccounts, usdcAsset);
    sm.createAccountForSM(manager);
  }

  function _mintAndDepositCash(uint accountId, uint amount) public {
    usdc.mint(address(this), amount);
    usdc.approve(address(usdcAsset), type(uint).max);
    usdcAsset.deposit(accountId, amount);
  }

  function _setupAccounts() public {
    alice = address(0xaa);
    bob = address(0xbb);
    charlie = address(0xcc);
    usdc.approve(address(usdcAsset), type(uint).max);

    aliceAcc = subAccounts.createAccountWithApproval(alice, address(this), manager);
    bobAcc = subAccounts.createAccountWithApproval(bob, address(this), manager);
    charlieAcc = subAccounts.createAccountWithApproval(charlie, address(this), manager);
  }

  //////////////////////////
  ///       Helpers      ///
  //////////////////////////

  function _getDefaultSolventParams() internal pure returns (IDutchAuction.SolventAuctionParams memory) {
    return IDutchAuction.SolventAuctionParams({
      startingMtMPercentage: 1e18,
      fastAuctionCutoffPercentage: 0.8e18,
      fastAuctionLength: 600,
      slowAuctionLength: 7200,
      liquidatorFeeRate: 0
    });
  }

  function _getDefaultInsolventParams() internal pure returns (IDutchAuction.InsolventAuctionParams memory) {
    return IDutchAuction.InsolventAuctionParams({length: 10 minutes, endingMtMScaler: 1.2e18});
  }
}
