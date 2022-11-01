// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "./MatchingPOCHelper.sol";
import "src/matching/SignedQuote.sol";

contract POC_SignedQuote is Test, MatchingPOCHelper {
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

  function testCanTradeQuote() public {
    uint subId = optionAdapter.addListing(1500e18, block.timestamp + 604800, true);

    // give quote wrapper allowance over both
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](2);
    assetAllowances[0] =
      AccountStructs.AssetAllowance({asset: IAsset(optionAdapter), positive: type(uint).max, negative: type(uint).max});
    assetAllowances[1] =
      AccountStructs.AssetAllowance({asset: IAsset(usdcAdapter), positive: type(uint).max, negative: type(uint).max});

    vm.startPrank(bob);
    account.setAssetAllowances(bobAcc, address(signedQuote), assetAllowances);
    vm.stopPrank();

    vm.startPrank(alice);
    account.setAssetAllowances(aliceAcc, address(signedQuote), assetAllowances);
    vm.stopPrank();

    SignedQuote.QuoteTransfer memory optionTransfer =
      SignedQuote.QuoteTransfer({asset: address(optionAdapter), subId: subId, amount: int(50e18)});

    SignedQuote.QuoteData memory quote = SignedQuote.QuoteData({
      fromAcc: bobAcc,
      toAcc: uint(0),
      transfer: optionTransfer,
      price: 1000e18,
      deadline: uint(block.timestamp + 30),
      quoteAddr: address(signedQuote),
      nonce: 0
    });

    vm.startPrank(alice);
    bytes32 quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(3, quoteHash);
    signedQuote.executeSignature(quote, SignedQuote.Signature(v, r, s), aliceAcc);

    assertEq(account.getBalance(aliceAcc, IAsset(optionAdapter), subId), optionTransfer.amount);
    assertEq(account.getBalance(bobAcc, IAsset(optionAdapter), subId), -optionTransfer.amount);
    vm.stopPrank();

    // check noonce to revert the repeat attempt
    vm.startPrank(alice);
    vm.expectRevert(bytes(""));
    signedQuote.executeSignature(quote, SignedQuote.Signature(v, r, s), aliceAcc);
    vm.stopPrank();

    // check higher noonce succeeding
    vm.startPrank(alice);
    quote = SignedQuote.QuoteData({
      fromAcc: bobAcc,
      toAcc: uint(0),
      transfer: optionTransfer,
      price: 1000e18,
      deadline: uint(block.timestamp + 30),
      quoteAddr: address(signedQuote),
      nonce: 1
    });
    quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    (v, r, s) = vm.sign(3, quoteHash);
    signedQuote.executeSignature(quote, SignedQuote.Signature(v, r, s), aliceAcc);
    vm.stopPrank();

    // check higher noonce deadline
    vm.startPrank(alice);
    quote = SignedQuote.QuoteData({
      fromAcc: bobAcc,
      toAcc: uint(0),
      transfer: optionTransfer,
      price: 1000e18,
      deadline: uint(block.timestamp + 30),
      quoteAddr: address(signedQuote),
      nonce: 2
    });
    quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    (v, r, s) = vm.sign(3, quoteHash);
    vm.warp(block.timestamp + 31);
    vm.expectRevert(bytes(""));
    signedQuote.executeSignature(quote, SignedQuote.Signature(v, r, s), aliceAcc);
    vm.stopPrank();

    // expect revert since Alice must be msg.sender to execute the quote
    vm.startPrank(bob);
    quote = SignedQuote.QuoteData({
      fromAcc: bobAcc,
      toAcc: uint(0),
      transfer: optionTransfer,
      price: 1000e18,
      deadline: uint(block.timestamp + 30),
      quoteAddr: address(signedQuote),
      nonce: 0
    });
    quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    (v, r, s) = vm.sign(3, quoteHash);
    vm.expectRevert(bytes(""));
    signedQuote.executeSignature(quote, SignedQuote.Signature(v, r, s), aliceAcc);
    vm.stopPrank();

    // expect revert since Alice signed, not Bob
    vm.startPrank(alice);
    quote = SignedQuote.QuoteData({
      fromAcc: bobAcc,
      toAcc: uint(0),
      transfer: optionTransfer,
      price: 1000e18,
      deadline: uint(block.timestamp + 30),
      quoteAddr: address(signedQuote),
      nonce: 0
    });
    quoteHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encode(quote))));
    (v, r, s) = vm.sign(2, quoteHash);
    vm.expectRevert(bytes(""));
    signedQuote.executeSignature(quote, SignedQuote.Signature(v, r, s), aliceAcc);
    vm.stopPrank();
  }
}
