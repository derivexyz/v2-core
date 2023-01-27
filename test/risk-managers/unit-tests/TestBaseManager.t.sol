pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin/token/ERC20/IERC20.sol";

import "src/interfaces/IManager.sol";
import "src/interfaces/ICashAsset.sol";
import "src/interfaces/IOption.sol";
import "src/interfaces/ISpotFeeds.sol";

import "src/Accounts.sol";
import "src/risk-managers/BaseManager.sol";

import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockFeed.sol";
import "../../shared/mocks/MockOption.sol";

contract BaseManagerTester is BaseManager {
  constructor(IAccounts accounts_, ISpotFeeds spotFeeds_, ICashAsset cash_, IOption option_)
    BaseManager(accounts_, spotFeeds_, cash_, option_)
  {}

  function symmetricManagerAdjustment(uint from, uint to, IAsset asset, uint96 subId, int amount) external {
    _symmetricManagerAdjustment(from, to, asset, subId, amount);
  }
}

contract UNIT_TestAbstractBaseManager is Test {
  Accounts accounts;
  BaseManagerTester tester;

  MockAsset mockAsset;
  MockFeed spotFeeds;
  MockERC20 usdc;
  MockOption option;
  MockAsset cash;

  address alice = address(0xaa);
  address bob = address(0xb0ba);

  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    accounts = new Accounts("Lyra Accounts", "LyraAccount");

    spotFeeds = new MockFeed();
    usdc = new MockERC20("USDC", "USDC");
    option = new MockOption(accounts);
    cash = new MockAsset(usdc, accounts, true);

    tester = new BaseManagerTester(accounts, spotFeeds, ICashAsset(address(cash)), option);

    mockAsset = new MockAsset(IERC20(address(0)), accounts, true);

    aliceAcc = accounts.createAccount(alice, IManager(address(tester)));

    bobAcc = accounts.createAccount(bob, IManager(address(tester)));
  }

  function testTransferWithoutMarginPositiveAmount() public {
    int amount = 5000 * 1e18;
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, amount);

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 0), -amount);
    assertEq(accounts.getBalance(bobAcc, mockAsset, 0), amount);
  }

  function testTransferWithoutMarginNegativeAmount() public {
    int amount = -5000 * 1e18;
    tester.symmetricManagerAdjustment(aliceAcc, bobAcc, mockAsset, 0, amount);

    assertEq(accounts.getBalance(aliceAcc, mockAsset, 0), -amount);
    assertEq(accounts.getBalance(bobAcc, mockAsset, 0), amount);
  }
}
