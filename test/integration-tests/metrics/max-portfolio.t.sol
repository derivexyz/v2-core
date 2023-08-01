// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import "lyra-utils/encoding/OptionEncoding.sol";

import "../shared/IntegrationTestBase.t.sol";

/**
 * @dev testing gas cost for both managers
 */
contract GAS_MAX_PORTFOLIO is IntegrationTestBase {
  using DecimalMath for uint;

  // value used for test
  int constant amountOfContracts = 1e18;

  uint64 expiry1;
  uint64 expiry2;

  uint bobPMRMAccEth;
  uint bobPMRMAccWbtc;

  function setUp() public {
    _setupIntegrationTestComplete();

    // setup pmrm accounts for bob
    bobPMRMAccEth = subAccounts.createAccountWithApproval(bob, address(this), markets["weth"].pmrm);
    bobPMRMAccWbtc = subAccounts.createAccountWithApproval(bob, address(this), markets["wbtc"].pmrm);

    // init setup for both accounts
    _depositCash(alice, aliceAcc, 1_000_000e18);
    _depositCash(bob, bobAcc, 1_000_000e18);
    _depositCash(bob, bobPMRMAccEth, 1_000_000e18);
    _depositCash(bob, bobPMRMAccWbtc, 1_000_000e18);

    expiry1 = uint64(block.timestamp) + 2 weeks;
    expiry2 = uint64(block.timestamp) + 4 weeks;

    // set all spot
    _setupAllFeedsForMarket("weth", expiry1, 2000e18);
    _setupAllFeedsForMarket("wbtc", expiry1, 15000e18);

    _setupAllFeedsForMarket("weth", expiry2, 2004e18);
    _setupAllFeedsForMarket("wbtc", expiry2, 15009e18);

    // don't need OI fee
    srm.setFeeBypassedCaller(address(this), true);
    markets["weth"].pmrm.setTrustedRiskAssessor(address(this), true);
    markets["wbtc"].pmrm.setTrustedRiskAssessor(address(this), true);

    srm.setMaxAccountSize(130);
  }

  /**
   * ---------------------------
   *      Standard Manager
   * ----------------------------
   */

  function testGas_SRM_SingleMarketSmall() public {
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 32, aliceAcc, bobAcc, 1e18, 10e18);

    console2.log("Gas Usage: (1 market, 1 expiry, 32 options)");
    _logMarginGas(bobAcc);
  }

  function testGas_SRM_SingleMarketBig() public {
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 64, aliceAcc, bobAcc, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, (2000 + 6400) * 1e18, 64, aliceAcc, bobAcc, 1e18, 10e18);

    console2.log("Gas Usage: (1 market, 1 expiry, 128 options)");
    _logMarginGas(bobAcc);
  }

  function testGas_SRM_SingleMarketMultiExpiry() public {
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 64, aliceAcc, bobAcc, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry2, 2000e18, 64, aliceAcc, bobAcc, 1e18, 10e18);

    console2.log("Gas Usage: (1 market, 2 expiries, 128 options)");
    _logMarginGas(bobAcc);
  }

  function testGas_SRM_TwoMarkets() public {
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 64, aliceAcc, bobAcc, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["wbtc"], expiry1, 15000e18, 64, aliceAcc, bobAcc, 1e18, 100e18);

    console2.log("Gas Usage: (2 market, 1 expiry, 128 options)");
    _logMarginGas(bobAcc);
  }

  function testGas_SRM_TwoMarkets4Expiries() public {
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 32, aliceAcc, bobAcc, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry2, 2000e18, 32, aliceAcc, bobAcc, 1e18, 10e18);

    _tradeOptionsPerMarketExpiry(markets["wbtc"], expiry1, 15000e18, 32, aliceAcc, bobAcc, 1e18, 50e18);
    _tradeOptionsPerMarketExpiry(markets["wbtc"], expiry2, 15000e18, 32, aliceAcc, bobAcc, 1e18, 50e18);

    console2.log("Gas Usage: (2 market, 2 expiries each, 128 options)");
    _logMarginGas(bobAcc);
  }

  function testGas_SRM_TwoMarkets_Perps() public {
    _tradePerp(markets["weth"], 1e18, 10e18, aliceAcc, bobAcc);
    _tradePerp(markets["wbtc"], 1e18, 10e18, bobAcc, aliceAcc);

    console2.log("Gas Usage: (2 market, 2 perps)");
    _logMarginGas(bobAcc);
  }

  /**
   * ---------------------------
   *            PMRM
   * ----------------------------
   */

  function testGas_PMRM_SingleExpiry() public {
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 64, aliceAcc, bobPMRMAccEth, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 9000e18, 63, aliceAcc, bobPMRMAccEth, 1e18, 10e18);

    console2.log("Gas Usage: (1 market, 1 expiry, 127 options)");
    _logMarginGas(bobPMRMAccEth);
  }

  function testGas_PMRM_2Expiries() public {
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 64, aliceAcc, bobPMRMAccEth, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry2, 2000e18, 63, aliceAcc, bobPMRMAccEth, 1e18, 10e18);

    console2.log("Gas Usage: (1 market, 2 expiries, 127 options)");
    _logMarginGas(bobPMRMAccEth);
  }

  function testGas_PMRM_FourExpiries() public {
    uint64 expiry3 = uint64(block.timestamp) + 6 weeks;
    uint64 expiry4 = uint64(block.timestamp) + 8 weeks;

    _setupAllFeedsForMarket("weth", expiry3, 2020e18);
    _setupAllFeedsForMarket("weth", expiry4, 2020e18);

    _tradeOptionsPerMarketExpiry(markets["weth"], expiry1, 2000e18, 32, aliceAcc, bobPMRMAccEth, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry2, 2000e18, 32, aliceAcc, bobPMRMAccEth, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry3, 2000e18, 32, aliceAcc, bobPMRMAccEth, 1e18, 10e18);
    _tradeOptionsPerMarketExpiry(markets["weth"], expiry4, 2000e18, 31, aliceAcc, bobPMRMAccEth, 1e18, 10e18);

    console2.log("Gas Usage: (1 market, 4 expiry, 127 options)");
    _logMarginGas(bobPMRMAccEth);
  }

  function testGas_PMRM_Only_Perps() public {
    _tradePerp(markets["weth"], 1e18, 10e18, aliceAcc, bobPMRMAccEth);

    console2.log("Gas Usage: (1 markets, 1 perps)");
    _logMarginGas(bobPMRMAccEth);
  }

  /**
   * ---------------------------
   *       Helper Functions
   * ----------------------------
   */

  function _tradeOptionsPerMarketExpiry(
    Market storage market,
    uint expiry,
    uint startingStrike,
    uint numOfOptions,
    uint buyer,
    uint seller,
    int unit,
    int unitPremium
  ) internal {
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](numOfOptions + 1);

    // for each option, buyer send cash to seller, seller send option to buyer
    for (uint i = 0; i < numOfOptions; i++) {
      uint strike = startingStrike + i * 100e18;
      uint subId = market.option.getSubId(expiry, strike, true);
      transferBatch[i + 1] = ISubAccounts.AssetTransfer({
        fromAcc: seller,
        toAcc: buyer,
        asset: market.option,
        subId: subId,
        amount: unit,
        assetData: bytes32(0)
      });
    }
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: buyer,
      toAcc: seller,
      asset: cash,
      subId: 0,
      amount: unitPremium * int(numOfOptions),
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");
  }

  function _tradePerp(Market storage market, int amount, int cashDiff, uint buyer, uint seller) internal {
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: buyer,
      toAcc: seller,
      asset: cash,
      subId: 0,
      amount: cashDiff,
      assetData: bytes32(0)
    });
    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: seller,
      toAcc: buyer,
      asset: market.perp,
      subId: 0,
      amount: amount,
      assetData: bytes32(0)
    });

    subAccounts.submitTransfers(transferBatch, "");
  }

  function _logMarginGas(uint account) internal view {
    uint gas = gasleft();
    srm.getMargin(account, true);
    uint gasUsed = gas - gasleft();

    uint totalAssets = subAccounts.getAccountBalances(account).length;
    console2.log("Total asset per account: ", totalAssets);
    console2.log("Margin check gas cost:", gasUsed);
  }

  function _setupAllFeedsForMarket(string memory market, uint64 expiry, uint96 spot) internal {
    _setSpotPrice(market, spot, 1e18);
    _setForwardPrice(market, expiry, spot, 1e18);
    _setDefaultSVIForExpiry(market, expiry);
  }
}
