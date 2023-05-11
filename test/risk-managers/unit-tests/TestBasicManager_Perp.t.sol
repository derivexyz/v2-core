pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/BasicManager.sol";

import "src/Accounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeed.sol";
import "test/shared/mocks/MockOptionPricing.sol";

import "test/auction/mocks/MockCashAsset.sol";

contract UNIT_TestBasicManager is Test {
  Accounts account;
  BasicManager manager;
  MockCash cash;
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

    cash = new MockCash(usdc, account);

    perp = new MockPerp(account);

    option = new MockOption(account);

    feed = new MockFeed();

    manager = new BasicManager(
      account,
      ICashAsset(address(cash))
    );

    manager.whitelistAsset(perp, 1, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(option, 1, IBasicManager.AssetType.Option);

    manager.setOraclesForMarket(1, feed, feed, feed);

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    feed.setSpot(1500e18);

    usdc.mint(address(this), 10000e18);
    usdc.approve(address(cash), type(uint).max);
  }

  /////////////
  // Setters //
  /////////////

  function testSetPricingModule() public {
    MockOptionPricing pricing = new MockOptionPricing();
    manager.setPricingModule(pricing);
    assertEq(address(manager.pricing()), address(pricing));
  }

  ////////////////////
  // Manager Change //
  ////////////////////

  function testValidManagerChange() public {
    MockManager newManager = new MockManager(address(account));

    // first fails the change
    vm.startPrank(alice);
    vm.expectRevert(IBasicManager.BM_NotWhitelistManager.selector);
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
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);
    vm.stopPrank();
  }

  function setPerpMarginRequirementsRatios() public {
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);
    (uint mmRequirement, uint imRequirement) = manager.perpMarginRequirements(1);

    assertEq(mmRequirement, 0.1e18);
    assertEq(imRequirement, 0.05e18);
  }

  function testCannotSetPerpMMLargerThanIM() public {
    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0.1e18, 0.05e18);
  }

  function testCannotSetInvalidPerpMarginRequirement() public {
    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0.1e18, 0);

    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0.1e18, 1e18);

    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 1e18, 0.1e18);
    vm.expectRevert(IBasicManager.BM_InvalidMarginRequirement.selector);
    manager.setPerpMarginRequirements(1, 0, 0.1e18);
  }

  ////////////////////
  //  Margin Checks //
  ////////////////////

  function testCannotHaveUnrecognizedAsset() public {
    MockAsset badAsset = new MockAsset(usdc, account, true);
    vm.expectRevert(IBasicManager.BM_UnsupportedAsset.selector);
    IAccounts.AssetTransfer memory transfer = IAccounts.AssetTransfer({
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
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1500e18);
    cash.deposit(bobAcc, 1500e18);

    // trade can go through
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
  }

  function testCannotTradePerpWithInsufficientMargin() public {
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);

    // trade 10 contracts, margin requirement = 10 * 1500 * 0.1 = 1500
    cash.deposit(aliceAcc, 1499e18);
    cash.deposit(bobAcc, 1499e18);

    // trade cannot go through
    vm.expectRevert(abi.encodeWithSelector(IBasicManager.BM_PortfolioBelowMargin.selector, aliceAcc, 1500e18));
    _tradePerpContract(aliceAcc, bobAcc, 10e18);
  }

  function _tradePerpContract(uint fromAcc, uint toAcc, int amount) internal {
    IAccounts.AssetTransfer memory transfer =
      IAccounts.AssetTransfer({fromAcc: fromAcc, toAcc: toAcc, asset: perp, subId: 0, amount: amount, assetData: ""});
    account.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, cash, 0);
  }
}
