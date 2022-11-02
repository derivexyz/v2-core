// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "./MatchingPOCHelper.sol";
import "src/matching/SignedVolComboQuote.sol";

contract POC_SignedVolComboQuote is Test, MatchingPOCHelper {
  uint aliceAcc;
  uint bobAcc;
  uint charlieAcc;
  uint davidAcc;

  function setUp() public {
    deployPRMSystem();
    setPrices(1e18, 1500e18);

    PortfolioRiskPOCManager.Scenario[] memory scenarios = new PortfolioRiskPOCManager.Scenario[](1);
    scenarios[0] = PortfolioRiskPOCManager.Scenario({spotShock: uint(85e16), ivShock: 10e18});

    setScenarios(scenarios);

    aliceAcc = createAccountAndDepositUSDC(alice, 10000000e18);
    bobAcc = createAccountAndDepositUSDC(bob, 10000000e18);
  }

  function testCanTradeVolSingleQuote() public {
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    // give quote wrapper allowance over both
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] =
      AccountStructs.AssetAllowance({asset: IAsset(optionAdapter), positive: type(uint).max, negative: type(uint).max});
    assetAllowances[1] =
      AccountStructs.AssetAllowance({asset: IAsset(usdcAdapter), positive: type(uint).max, negative: type(uint).max});

    vm.startPrank(bob);
    account.setAssetAllowances(bobAcc, address(signedVolComboQuote), assetAllowances);
    vm.stopPrank();

    vm.startPrank(alice);
    account.setAssetAllowances(aliceAcc, address(signedVolComboQuote), assetAllowances);
    vm.stopPrank();

    SignedVolComboQuote.TransferData[] memory transfers = new SignedVolComboQuote.TransferData[](1);
    SignedVolComboQuote.PricingData[] memory bids = new SignedVolComboQuote.PricingData[](1);
    SignedVolComboQuote.PricingData[] memory asks = new SignedVolComboQuote.PricingData[](1);
    transfers[0] = SignedVolComboQuote.TransferData({
      asset: address(optionAdapter),
      subId: uint96(subId),
      amount: int(50e18)
    });
    bids[0] = SignedVolComboQuote.PricingData({
      volatility: uint128(0.9e18),
      fwdSpread: int128(-2e18-0.1e18), // $2 dividend, bob's bid fwd is smaller since he expects to pay for a hedge
      discount: uint64(1e18)
    });
    asks[0] = SignedVolComboQuote.PricingData({
      volatility: uint128(0.91e18),
      fwdSpread: int128(-2e18+0.1e18), // $2 dividend, if bob is selling, he prices fwd a little higher
      discount: uint64(1e18)
    });

    SignedVolComboQuote.QuoteComboData memory quote = SignedVolComboQuote.QuoteComboData({
      fromAcc: bobAcc,
      toAcc: uint(0),
      transfers: transfers,
      bids: bids,
      asks: asks,
      deadline: uint(block.timestamp + 30),
      quoteAddr: address(signedVolComboQuote),
      nonce: 0
    });

    vm.startPrank(alice);
    bytes32 quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    SignedVolComboQuote.CallerArgs memory callerArgs = SignedVolComboQuote.CallerArgs({
      toAcc: aliceAcc,
      isBuying: true,
      limitPrice: 0
    });
    callerArgs.limitPrice = signedVolComboQuote.volComboQuoteToPrice(callerArgs, quote);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(3, quoteHash);
    
    signedVolComboQuote.executeSignature(callerArgs, quote, SignedVolComboQuote.Signature(v,r,s));

    assertEq(account.getBalance(aliceAcc, IAsset(optionAdapter), subId), transfers[0].amount);
    assertEq(account.getBalance(bobAcc, IAsset(optionAdapter), subId), -transfers[0].amount);

    assertEq(account.getBalance(aliceAcc, IAsset(usdcAdapter), subId), int(10000000e18)-callerArgs.limitPrice);
    assertEq(account.getBalance(bobAcc, IAsset(usdcAdapter), subId), int(10000000e18)+callerArgs.limitPrice);
    vm.stopPrank();

  }
}
