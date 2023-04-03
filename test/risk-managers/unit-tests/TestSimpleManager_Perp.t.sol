pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/SimpleManager.sol";

import "src/Accounts.sol";
import "src/interfaces/IManager.sol";
import "src/interfaces/IAsset.sol";
import "src/interfaces/AccountStructs.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeed.sol";

contract UNIT_TestSimpleManager is Test {
  Accounts account;
  SimpleManager manager;
  MockAsset cash;
  MockERC20 usdc;
  MockPerp perp;
  MockOption option;

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

    manager = new SimpleManager(
      account,
      ICashAsset(address(cash)),
      option,
      perp,
      feed
    );

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    feed.setSpot(1500e18);

    usdc.mint(address(this), 10000e18);
    usdc.approve(address(cash), type(uint).max);
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));

    // first fails the change
    vm.startPrank(alice);
    vm.expectRevert(ISimpleManager.PM_NotWhitelistManager.selector);
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();

    manager.setWhitelistManager(address(newManager), true);
    vm.startPrank(alice);
    account.changeManager(aliceAcc, IManager(address(newManager)), "");
    vm.stopPrank();
  }

  ////////////////////////////
  // Set Margin Requirement //
  ////////////////////////////

  function testCannotSetPerpMarginRequirementFromNonOwner() public {
    vm.startPrank(alice);
    vm.expectRevert();
    manager.setPerpMarginRequirements(0.05e18, 0.1e18);
    vm.stopPrank();
  }

  function setPerpMarginRequirementsRatios() public {
    manager.setPerpMarginRequirements(0.05e18, 0.1e18);

    assertEq(manager.perpMMRequirement(), 0.1e18);
    assertEq(manager.perpIMRequirement(), 0.05e18);
  }

  function testCannotSetPerpMMLargerThanIM() public {
    vm.expectRevert(ISimpleManager.PM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(0.1e18, 0.05e18);
  }

  function testCannotSetInvalidPerpMarginRequirement() public {
    vm.expectRevert(ISimpleManager.PM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(0.1e18, 0);

    vm.expectRevert(ISimpleManager.PM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(0.1e18, 1e18);

    vm.expectRevert(ISimpleManager.PM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1e18, 0.1e18);
    vm.expectRevert(ISimpleManager.PM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(0, 0.1e18);
  }

  ////////////////////
  //  Margin Checks //
  ////////////////////

  function testCannotHaveUnrecognizedAsset() public {
    MockAsset badAsset = new MockAsset(usdc, account, true);
    vm.expectRevert(ISimpleManager.PM_UnsupportedAsset.selector);
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: aliceAcc,
      toAcc: bobAcc,
      asset: badAsset,
      subId: 0,
      amount: 1e18,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }

  function testCanTradePerpWithEnoughMargin() public {
    manager.setPerpMarginRequirements(0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1500e18);
    cash.deposit(bobAcc, 1500e18);

    // trade can go through
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
  }

  function testCannotTradePerpWithInsufficientMargin() public {
    manager.setPerpMarginRequirements(0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1499e18);
    cash.deposit(bobAcc, 1499e18);

    // trade cannot go through
    vm.expectRevert(abi.encodeWithSelector(ISimpleManager.PM_PortfolioBelowMargin.selector, aliceAcc, 1500e18));
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
    vm.stopPrank();
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
