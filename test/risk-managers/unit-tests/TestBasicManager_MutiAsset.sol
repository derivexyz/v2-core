pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "src/risk-managers/BasicManager.sol";

import "lyra-utils/encoding/OptionEncoding.sol";

import "src/Accounts.sol";
import {IManager} from "src/interfaces/IManager.sol";
import {IAsset} from "src/interfaces/IAsset.sol";

import "test/shared/mocks/MockManager.sol";
import "test/shared/mocks/MockERC20.sol";
import "test/shared/mocks/MockPerp.sol";
import "test/shared/mocks/MockOption.sol";
import "test/shared/mocks/MockFeed.sol";
import "test/shared/mocks/MockOptionPricing.sol";

/**
 * Focusing on the margin rules for options
 */
contract UNIT_TestBasicManager_MultiAsset is Test {
  Accounts account;
  BasicManager manager;
  MockAsset cash;
  MockERC20 usdc;

  MockPerp ethPerp;
  MockPerp btcPerp;
  MockOption ethOption;
  MockOption btcOption;

  MockOptionPricing pricing;
  uint expiry;

  MockFeed ethFeed;
  MockFeed btcFeed;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  function setUp() public {
    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    usdc = new MockERC20("USDC", "USDC");

    cash = new MockAsset(usdc, account, true);

    // Setup asset for ETH Markets
    ethPerp = new MockPerp(account);
    ethOption = new MockOption(account);
    ethFeed = new MockFeed();

    // setup asset for BTC Markets
    btcPerp = new MockPerp(account);
    btcOption = new MockOption(account);
    btcFeed = new MockFeed();

    pricing = new MockOptionPricing();

    manager = new BasicManager(
      account,
      ICashAsset(address(cash))
    );

    manager.setPricingModule(pricing);

    manager.whitelistAsset(ethPerp, 1, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(ethOption, 1, IBasicManager.AssetType.Option);
    manager.setOraclesForMarket(1, ethFeed, ethFeed, ethFeed);

    manager.whitelistAsset(btcPerp, 2, IBasicManager.AssetType.Perpetual);
    manager.whitelistAsset(btcOption, 2, IBasicManager.AssetType.Option);
    manager.setOraclesForMarket(2, btcFeed, btcFeed, btcFeed);

    aliceAcc = account.createAccountWithApproval(alice, address(this), manager);
    bobAcc = account.createAccountWithApproval(bob, address(this), manager);

    // set a future price that will be used for 90 day options
    expiry = block.timestamp + 91 days;
    ethFeed.setSpot(1500e18);
    btcFeed.setSpot(20000e18);

    usdc.mint(address(this), 100_000e18);
    usdc.approve(address(cash), type(uint).max);

    // set init perp trading parameters
    manager.setPerpMarginRequirements(0.05e18, 0.1e18);

    IBasicManager.OptionMarginParameters memory params =
      IBasicManager.OptionMarginParameters(0.2e18, 0.1e18, 0.08e18, 0.125e18);

    manager.setOptionMarginParameters(params);
  }

  function testCanTradeMultipleMarkets() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    int ethMargin = manager.getIsolatedMargin(1, ethStrike, expiry, true, -1e18, false);
    int btcMargin = manager.getIsolatedMargin(2, btcStrike, expiry, true, -1e18, false);

    int neededMargin = ethMargin + btcMargin;
    cash.deposit(aliceAcc, uint(-neededMargin));

    // short 1 eth call + 1 btc call
    _tradeOption(ethOption, aliceAcc, bobAcc, 1e18, expiry, ethStrike, true);
    _tradeOption(btcOption, aliceAcc, bobAcc, 1e18, expiry, btcStrike, true);

    int requirement = manager.getMargin(aliceAcc);
    assertEq(requirement, neededMargin);
  }

  /////////////
  // Helpers //
  /////////////

  function _tradeOption(IOption option, uint fromAcc, uint toAcc, int amount, uint _expiry, uint strike, bool isCall)
    internal
  {
    IAccounts.AssetTransfer memory transfer = IAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: option,
      subId: OptionEncoding.toSubId(_expiry, strike, isCall),
      amount: amount,
      assetData: ""
    });
    account.submitTransfer(transfer, "");
  }

  function _getCashBalance(uint acc) public view returns (int) {
    return account.getBalance(acc, cash, 0);
  }
}
