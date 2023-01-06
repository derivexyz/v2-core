// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "openzeppelin/utils/cryptography/ECDSA.sol";

import "../../../src/Accounts.sol";
import "../../../src/libraries/PermitAllowanceLib.sol";

import {MockManager} from "../../shared/mocks/MockManager.sol";
import {MockAsset} from "../../shared/mocks/MockAsset.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_AccountPermit is Test, AccountTestBase, AccountStructs {
  uint private immutable privateKey;
  uint private immutable privateKey2;
  address private immutable pkOwner;
  address private immutable pkOwner2;
  bytes32 public domainSeparator;

  uint accountId;
  uint accountId2;
  uint positiveAmount = 1e18;
  uint negativeAmount = 2e18;

  constructor() {
    privateKey = 0xBEEF;
    privateKey2 = 0xBEEF2;
    pkOwner = vm.addr(privateKey);
    pkOwner2 = vm.addr(privateKey2);
  }

  function setUp() public {
    vm.chainId(1);

    setUpAccounts();

    domainSeparator = account.domainSeparator();

    // get a account for pkOwner
    accountId = account.createAccount(pkOwner, dumbManager);

    accountId2 = account.createAccount(pkOwner2, dumbManager);
  }

  function testPermitCannotPermitWithExpiredSignature() public {
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](0);
    SubIdAllowance[] memory subIdAllowances = new SubIdAllowance[](0);

    PermitAllowance memory permit = PermitAllowance({
      delegate: alice,
      nonce: 0,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    vm.warp(block.timestamp + 10);

    bytes memory sig = _signPermit(privateKey, permit);

    vm.expectRevert(IAccounts.AC_SignatureExpired.selector);
    account.permit(permit, sig);
  }

  function testPermitCannotPermitWithFakeSignature() public {
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](0);
    SubIdAllowance[] memory subIdAllowances = new SubIdAllowance[](0);
    PermitAllowance memory permit = PermitAllowance({
      delegate: alice,
      nonce: 0,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    // use a bad private key to sign
    bytes memory sig = _signPermit(0x0fac, permit);

    vm.expectRevert(IAccounts.AC_InvalidPermitSignature.selector);
    account.permit(permit, sig);
  }

  function testPermitCanUpdateAssetAllowance() public {
    uint nonce = 1;
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](1);
    assetAllowances[0] = AssetAllowance(usdcAsset, positiveAmount, negativeAmount);
    SubIdAllowance[] memory subIdAllowances = new SubIdAllowance[](0);

    PermitAllowance memory permit = _getDefaultPermitUSDC(accountId, alice, nonce, positiveAmount, negativeAmount);

    bytes memory sig = _signPermit(privateKey, permit);
    account.permit(permit, sig);

    assertEq(account.positiveAssetAllowance(accountId, pkOwner, usdcAsset, alice), positiveAmount);
    assertEq(account.negativeAssetAllowance(accountId, pkOwner, usdcAsset, alice), negativeAmount);
  }

  function testPermitCanUpdateSubIdAllowance() public {
    uint96 subId = 0;
    uint nonce = 1;
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](0);
    SubIdAllowance[] memory subIdAllowances = new SubIdAllowance[](1);
    subIdAllowances[0] = SubIdAllowance(usdcAsset, subId, positiveAmount, negativeAmount);

    PermitAllowance memory permit = PermitAllowance({
      delegate: alice,
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);
    account.permit(permit, sig);

    assertEq(account.positiveSubIdAllowance(accountId, pkOwner, usdcAsset, subId, alice), positiveAmount);
    assertEq(account.negativeSubIdAllowance(accountId, pkOwner, usdcAsset, subId, alice), negativeAmount);
  }

  function testCannotReuseSignature() public {
    uint96 subId = 0;
    uint nonce = 1;
    PermitAllowance memory permit = _getDefaultPermitUSDC(accountId, alice, nonce, positiveAmount, negativeAmount);

    bytes memory sig = _signPermit(privateKey, permit);
    // first permit should pass
    account.permit(permit, sig);

    vm.expectRevert(IAccounts.AC_InvalidNonce.selector);
    account.permit(permit, sig);
  }

  function testCanUseNonceInArbitraryOrder() public {
    uint nonce1 = 20;
    PermitAllowance memory permit = _getDefaultPermitUSDC(accountId, alice, nonce1, positiveAmount, negativeAmount);
    bytes memory sig = _signPermit(privateKey, permit);
    account.permit(permit, sig);

    // the second permit: use a lower nonce for bob
    uint nonce2 = 1;
    PermitAllowance memory permit2 = _getDefaultPermitUSDC(accountId, bob, nonce2, positiveAmount, negativeAmount);
    bytes memory sig2 = _signPermit(privateKey, permit2);

    // this should still pass
    account.permit(permit2, sig2);
  }

  function testCanInvalidUpTo256NoncesAtATime() public {
    // use 2^256 as mask, mark all 256 bits as "used"
    uint mask = type(uint).max;
    // disable the first 256-bit bit map
    uint wordPos = 0;

    // only invalidate the first 256 nonces
    vm.prank(pkOwner);
    account.invalidateUnorderedNonces(wordPos, mask);

    uint nonce = 0;
    PermitAllowance memory permit = _getDefaultPermitUSDC(accountId, alice, nonce, positiveAmount, negativeAmount);
    bytes memory sig = _signPermit(privateKey, permit);
    vm.expectRevert(IAccounts.AC_InvalidNonce.selector);
    account.permit(permit, sig);

    uint nonce2 = 255;
    PermitAllowance memory permit2 = _getDefaultPermitUSDC(accountId, bob, nonce2, positiveAmount, negativeAmount);
    bytes memory sig2 = _signPermit(privateKey, permit2);

    vm.expectRevert(IAccounts.AC_InvalidNonce.selector);
    account.permit(permit2, sig2);

    // can use nonce > 255
    uint nonce3 = 256;
    PermitAllowance memory permit3 = _getDefaultPermitUSDC(accountId, bob, nonce3, positiveAmount, negativeAmount);
    bytes memory sig3 = _signPermit(privateKey, permit3);
    account.permit(permit3, sig3);
  }

  function testCannotReplayAttack() public {
    uint96 subId = 0;
    uint nonce = 1;
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](0);
    SubIdAllowance[] memory subIdAllowances = new SubIdAllowance[](1);
    subIdAllowances[0] = SubIdAllowance(usdcAsset, subId, positiveAmount, negativeAmount);

    PermitAllowance memory permit = PermitAllowance({
      delegate: alice,
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);

    vm.chainId(31337);

    vm.expectRevert(IAccounts.AC_InvalidPermitSignature.selector);
    account.permit(permit, sig);
  }

  function testPermitAndTransfer() public {
    // deposit 1000 USDC to "accountId"
    mintAndDeposit(alice, accountId, usdc, usdcAsset, 0, 1000e18);

    uint nonce = 5;
    uint96 subId = 0;
    uint allowanceAmount = 500e18;

    // sign signature to approve asset allowance + subId for 500 each
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](1);
    assetAllowances[0] = AssetAllowance(usdcAsset, 0, allowanceAmount);
    SubIdAllowance[] memory subIdAllowances = new SubIdAllowance[](1);
    subIdAllowances[0] = SubIdAllowance(usdcAsset, subId, 0, allowanceAmount);

    PermitAllowance memory permit = PermitAllowance({
      delegate: bob, //
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);

    // bob send transfer to send money to himself!
    AssetTransfer memory transfer = AssetTransfer({
      fromAcc: accountId,
      toAcc: bobAcc,
      asset: usdcAsset,
      subId: subId,
      amount: 1000e18,
      assetData: bytes32(0)
    });

    int bobUsdcBefore = account.getBalance(bobAcc, usdcAsset, subId);

    vm.startPrank(bob);
    account.permitAndSubmitTransfer(transfer, "", permit, sig);

    int bobUsdcAfter = account.getBalance(bobAcc, usdcAsset, subId);

    assertEq(bobUsdcAfter - bobUsdcBefore, 1000e18);

    // allowance is consumed immediately
    assertEq(account.positiveAssetAllowance(accountId, pkOwner, usdcAsset, bob), 0);
    assertEq(account.negativeAssetAllowance(accountId, pkOwner, usdcAsset, bob), 0);
  }

  function testBatchedPermitAndTransfers() public {
    uint tradeAmount = 1000e18;

    // deposit 1000 USDC to "accountId"
    mintAndDeposit(alice, accountId, usdc, usdcAsset, 0, tradeAmount);

    // depost 1000 coolToken for account2
    mintAndDeposit(alice, accountId2, coolToken, coolAsset, tokenSubId, tradeAmount);

    // premits and signature arrays
    PermitAllowance[] memory permits = new PermitAllowance[](2);
    bytes[] memory signatures = new bytes[](2);

    address orderbook = address(0xb00c);

    // owner1:  sign to approve asset allowance for USDC
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](1);
    assetAllowances[0] = AssetAllowance(usdcAsset, 0, tradeAmount);

    permits[0] = PermitAllowance({
      delegate: orderbook, // approve orderbook
      nonce: 1,
      accountId: accountId,
      deadline: block.timestamp,
      assetAllowances: assetAllowances,
      subIdAllowances: new SubIdAllowance[](0)
    });
    signatures[0] = _signPermit(privateKey, permits[0]);

    // owner2: sign to approve asset allowance for coolAsset
    AssetAllowance[] memory assetAllowances2 = new AssetAllowance[](1);
    assetAllowances2[0] = AssetAllowance(coolAsset, tokenSubId, tradeAmount);

    permits[1] = PermitAllowance({
      delegate: orderbook, // approve orderbook
      nonce: 1,
      accountId: accountId2,
      deadline: block.timestamp,
      assetAllowances: assetAllowances2,
      subIdAllowances: new SubIdAllowance[](0)
    });
    signatures[1] = _signPermit(privateKey2, permits[1]);

    // orderbook will submit a trade to exchange USDC <> CoolToken
    AssetTransfer[] memory transferBatch = new AssetTransfer[](2);
    transferBatch[0] = AssetTransfer({
      fromAcc: accountId,
      toAcc: accountId2,
      asset: IAsset(usdcAsset),
      subId: 0,
      amount: int(tradeAmount),
      assetData: bytes32(0)
    });
    transferBatch[1] = AssetTransfer({
      fromAcc: accountId2,
      toAcc: accountId,
      asset: IAsset(coolAsset),
      subId: tokenSubId,
      amount: int(tradeAmount),
      assetData: bytes32(0)
    });

    int acc1UsdBefore = account.getBalance(accountId, usdcAsset, 0);
    int acc1CoolBefore = account.getBalance(accountId, coolAsset, tokenSubId);
    int acc2UsdBefore = account.getBalance(accountId2, usdcAsset, 0);
    int acc2CoolBefore = account.getBalance(accountId2, coolAsset, tokenSubId);

    vm.prank(orderbook);
    account.permitAndSubmitTransfers(transferBatch, "", permits, signatures);

    // allowance is consumed immediately
    assertEq(account.negativeAssetAllowance(accountId, pkOwner, usdcAsset, orderbook), 0);
    assertEq(account.negativeAssetAllowance(accountId2, pkOwner2, coolAsset, orderbook), 0);

    int acc1UsdAfter = account.getBalance(accountId, usdcAsset, 0);
    int acc1CoolAfter = account.getBalance(accountId, coolAsset, tokenSubId);
    int acc2UsdAfter = account.getBalance(accountId2, usdcAsset, 0);
    int acc2CoolAfter = account.getBalance(accountId2, coolAsset, tokenSubId);

    // make sure trades went through
    assertEq(acc1UsdBefore - acc1UsdAfter, 1000e18);
    assertEq(acc1CoolAfter - acc1CoolBefore, 1000e18);

    assertEq(acc2UsdAfter - acc2UsdBefore, 1000e18);
    assertEq(acc2CoolBefore - acc2CoolAfter, 1000e18);
  }

  function testDomainSeparator() public view {
    // just for coverage for now
    account.domainSeparator();
  }

  function _getDefaultPermitUSDC(uint accountId, address spender, uint nonce, uint positiveAmount, uint negativeAmount)
    internal
    returns (PermitAllowance memory)
  {
    AssetAllowance[] memory assetAllowances = new AssetAllowance[](1);
    SubIdAllowance[] memory subIdAllowances = new SubIdAllowance[](0);
    assetAllowances[0] = AssetAllowance(usdcAsset, positiveAmount, negativeAmount);

    PermitAllowance memory permit = PermitAllowance({
      delegate: spender,
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    return permit;
  }

  function _signPermit(uint pk, PermitAllowance memory permit) internal view returns (bytes memory) {
    bytes32 structHash = PermitAllowanceLib.hash(permit);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
