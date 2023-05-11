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
  uint expiry1;
  uint expiry2;
  uint expiry3;

  MockFeed ethFeed;
  MockFeed btcFeed;

  address alice = address(0xaa);
  address bob = address(0xbb);
  uint aliceAcc;
  uint bobAcc;

  struct Trade {
    IOption option;
    int amount;
    uint expiry;
    uint strike;
    bool isCall;
  }

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

    expiry1 = block.timestamp + 7 days;
    expiry2 = block.timestamp + 14 days;
    expiry3 = block.timestamp + 30 days;

    ethFeed.setSpot(1500e18);
    btcFeed.setSpot(20000e18);

    usdc.mint(address(this), 100_000e18);
    usdc.approve(address(cash), type(uint).max);

    // set init perp trading parameters
    manager.setPerpMarginRequirements(1, 0.05e18, 0.1e18);

    IBasicManager.OptionMarginParameters memory params =
      IBasicManager.OptionMarginParameters(0.2e18, 0.1e18, 0.08e18, 0.125e18);

    manager.setOptionMarginParameters(1, params);
  }

  function testCanTradeMultipleMarkets() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    int ethMargin = manager.getIsolatedMargin(1, ethStrike, expiry1, true, -1e18, false);
    int btcMargin = manager.getIsolatedMargin(2, btcStrike, expiry1, true, -1e18, false);

    int neededMargin = ethMargin + btcMargin;
    cash.deposit(aliceAcc, uint(-neededMargin));

    // short 1 eth call + 1 btc call
    Trade[] memory trades = new Trade[](2);
    trades[0] = Trade(ethOption, 1e18, expiry1, ethStrike, true);
    trades[1] = Trade(btcOption, 1e18, expiry1, btcStrike, true);
    _submitMultipleTrades(aliceAcc, bobAcc, trades);

    int requirement = manager.getMargin(aliceAcc, false);
    assertEq(requirement, neededMargin);
  }

  function testCanTradeMultiMarketMultiExpiry() public {
    // summarize the initial margin for 2 options
    uint ethStrike = 2000e18;
    uint btcStrike = 30000e18;
    int ethMargin1 = manager.getIsolatedMargin(1, ethStrike, expiry1, true, -1e18, false);
    int btcMargin1 = manager.getIsolatedMargin(2, btcStrike, expiry1, true, -1e18, false);
    int ethMargin2 = manager.getIsolatedMargin(1, ethStrike, expiry2, true, -1e18, false);
    int btcMargin2 = manager.getIsolatedMargin(2, btcStrike, expiry2, true, -1e18, false);

    int neededMargin = ethMargin1 + btcMargin1 + ethMargin2 + btcMargin2;
    cash.deposit(aliceAcc, uint(-neededMargin));

    Trade[] memory trades = new Trade[](4);
    trades[0] = Trade(ethOption, 1e18, expiry1, ethStrike, true);
    trades[1] = Trade(btcOption, 1e18, expiry1, btcStrike, true);
    trades[2] = Trade(ethOption, 1e18, expiry2, ethStrike, true);
    trades[3] = Trade(btcOption, 1e18, expiry2, btcStrike, true);

    // short 1 eth call + 1 btc call
    _submitMultipleTrades(aliceAcc, bobAcc, trades);

    int requirement = manager.getMargin(aliceAcc, false);
    assertEq(requirement, neededMargin);
  }

  /////////////
  // Helpers //
  /////////////

  function _submitMultipleTrades(uint from, uint to, Trade[] memory trades) internal {
    IAccounts.AssetTransfer[] memory transfers = new IAccounts.AssetTransfer[](trades.length);
    for (uint i = 0; i < trades.length; i++) {
      transfers[i] = IAccounts.AssetTransfer({
        fromAcc: from,
        toAcc: to,
        asset: trades[i].option,
        subId: OptionEncoding.toSubId(trades[i].expiry, trades[i].strike, trades[i].isCall),
        amount: trades[i].amount,
        assetData: ""
      });
    }
    account.submitTransfers(transfers, "");
  }

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
