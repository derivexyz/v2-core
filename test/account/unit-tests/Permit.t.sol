// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "openzeppelin/utils/cryptography/ECDSA.sol";

import "../../../src/SubAccounts.sol";
import "../../../src/libraries/PermitAllowanceLib.sol";

import {MockManager} from "../../shared/mocks/MockManager.sol";
import {MockAsset} from "../../shared/mocks/MockAsset.sol";

import {AccountTestBase} from "./AccountTestBase.sol";

contract UNIT_AccountPermit is Test, AccountTestBase {
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

    domainSeparator = subAccounts.domainSeparator();

    // get a account for pkOwner
    accountId = subAccounts.createAccount(pkOwner, dumbManager);

    accountId2 = subAccounts.createAccount(pkOwner2, dumbManager);
  }

  function testPermitCannotPermitWithExpiredSignature() public {
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](0);
    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](0);

    IAllowances.PermitAllowance memory permit = IAllowances.PermitAllowance({
      delegate: alice,
      nonce: 0,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    vm.warp(block.timestamp + 10);

    bytes memory sig = _signPermit(privateKey, permit);

    vm.expectRevert(ISubAccounts.AC_SignatureExpired.selector);
    subAccounts.permit(permit, sig);
  }

  function testPermitCannotPermitWithFakeSignature() public {
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](0);
    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](0);
    IAllowances.PermitAllowance memory permit = IAllowances.PermitAllowance({
      delegate: alice,
      nonce: 0,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    // use a bad private key to sign
    bytes memory sig = _signPermit(0x0fac, permit);

    vm.expectRevert(ISubAccounts.AC_InvalidPermitSignature.selector);
    subAccounts.permit(permit, sig);
  }

  function testPermitCanUpdateAssetAllowance() public {
    uint nonce = 1;
    IAllowances.PermitAllowance memory permit =
      _getAssetPermitUSDC(accountId, alice, nonce, positiveAmount, negativeAmount);
    bytes memory sig = _signPermit(privateKey, permit);
    subAccounts.permit(permit, sig);

    assertEq(subAccounts.positiveAssetAllowance(accountId, pkOwner, usdcAsset, alice), positiveAmount);
    assertEq(subAccounts.negativeAssetAllowance(accountId, pkOwner, usdcAsset, alice), negativeAmount);
  }

  function testPermitCanUpdateSubIdAllowance() public {
    uint96 subId = 0;
    uint nonce = 1;
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](0);
    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](1);
    subIdAllowances[0] = IAllowances.SubIdAllowance(usdcAsset, subId, positiveAmount, negativeAmount);

    IAllowances.PermitAllowance memory permit = IAllowances.PermitAllowance({
      delegate: alice,
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);
    subAccounts.permit(permit, sig);

    assertEq(subAccounts.positiveSubIdAllowance(accountId, pkOwner, usdcAsset, subId, alice), positiveAmount);
    assertEq(subAccounts.negativeSubIdAllowance(accountId, pkOwner, usdcAsset, subId, alice), negativeAmount);
  }

  function testCannotReuseSignature() public {
    uint nonce = 1;
    IAllowances.PermitAllowance memory permit =
      _getAssetPermitUSDC(accountId, alice, nonce, positiveAmount, negativeAmount);

    bytes memory sig = _signPermit(privateKey, permit);
    // first permit should pass
    subAccounts.permit(permit, sig);

    vm.expectRevert(ISubAccounts.AC_InvalidNonce.selector);
    subAccounts.permit(permit, sig);
  }

  function testCanUseNonceInArbitraryOrder() public {
    uint nonce1 = 20;
    IAllowances.PermitAllowance memory permit =
      _getAssetPermitUSDC(accountId, alice, nonce1, positiveAmount, negativeAmount);
    bytes memory sig = _signPermit(privateKey, permit);
    subAccounts.permit(permit, sig);

    // the second permit: use a lower nonce for bob
    uint nonce2 = 1;
    IAllowances.PermitAllowance memory permit2 =
      _getAssetPermitUSDC(accountId, bob, nonce2, positiveAmount, negativeAmount);
    bytes memory sig2 = _signPermit(privateKey, permit2);

    // this should still pass
    subAccounts.permit(permit2, sig2);
  }

  function testCanInvalidateSpecificNoncesInBatch() public {
    uint nonce1 = 1;
    uint nonce2 = 200;
    uint nonce3 = 250;

    uint mask = 1 << nonce1 | 1 << nonce2 | 1 << nonce3;
    // all these 3 nonces belongs to the first 256-bit bit map. (< 256)
    uint wordPos = 0;

    // only invalidate these 3 nonces
    vm.prank(pkOwner);
    subAccounts.invalidateUnorderedNonces(wordPos, mask);

    // first nonce is invalid
    IAllowances.PermitAllowance memory permit =
      _getAssetPermitUSDC(accountId, alice, nonce1, positiveAmount, negativeAmount);
    bytes memory sig = _signPermit(privateKey, permit);
    vm.expectRevert(ISubAccounts.AC_InvalidNonce.selector);
    subAccounts.permit(permit, sig);

    // second nonce is invalid
    permit = _getAssetPermitUSDC(accountId, alice, nonce2, positiveAmount, negativeAmount);
    sig = _signPermit(privateKey, permit);
    vm.expectRevert(ISubAccounts.AC_InvalidNonce.selector);
    subAccounts.permit(permit, sig);

    // third nonce is invalid
    permit = _getAssetPermitUSDC(accountId, alice, nonce3, positiveAmount, negativeAmount);
    sig = _signPermit(privateKey, permit);
    vm.expectRevert(ISubAccounts.AC_InvalidNonce.selector);
    subAccounts.permit(permit, sig);

    // can use any other nonce
    uint validNonce = 2;
    permit = _getAssetPermitUSDC(accountId, bob, validNonce, positiveAmount, negativeAmount);
    sig = _signPermit(privateKey, permit);
    subAccounts.permit(permit, sig);
  }

  function testCanInvalidateUpTo256NoncesAtATime() public {
    // use 2^256 as mask, mark all 256 bits as "used"
    uint mask = type(uint).max;
    // disable the first 256-bit bit map
    uint wordPos = 0;

    // only invalidate the first 256 nonces
    vm.prank(pkOwner);
    subAccounts.invalidateUnorderedNonces(wordPos, mask);

    uint nonce = 0;
    IAllowances.PermitAllowance memory permit =
      _getAssetPermitUSDC(accountId, alice, nonce, positiveAmount, negativeAmount);
    bytes memory sig = _signPermit(privateKey, permit);
    vm.expectRevert(ISubAccounts.AC_InvalidNonce.selector);
    subAccounts.permit(permit, sig);

    uint nonce2 = 255;
    IAllowances.PermitAllowance memory permit2 =
      _getAssetPermitUSDC(accountId, bob, nonce2, positiveAmount, negativeAmount);
    bytes memory sig2 = _signPermit(privateKey, permit2);

    vm.expectRevert(ISubAccounts.AC_InvalidNonce.selector);
    subAccounts.permit(permit2, sig2);

    // can use nonce > 255
    uint nonce3 = 256;
    IAllowances.PermitAllowance memory permit3 =
      _getAssetPermitUSDC(accountId, bob, nonce3, positiveAmount, negativeAmount);
    bytes memory sig3 = _signPermit(privateKey, permit3);
    subAccounts.permit(permit3, sig3);
  }

  function testCannotReplayAttack() public {
    uint nonce = 1;

    IAllowances.PermitAllowance memory permit =
      _getAssetPermitUSDC(accountId, alice, nonce, positiveAmount, negativeAmount);
    bytes memory sig = _signPermit(privateKey, permit);

    vm.chainId(31337);
    vm.expectRevert(ISubAccounts.AC_InvalidPermitSignature.selector);
    subAccounts.permit(permit, sig);
  }

  function testPermitAndTransfer() public {
    // deposit 1000 USDC to "accountId"
    mintAndDeposit(alice, accountId, usdc, usdcAsset, 0, 1000e18);

    uint nonce = 5;
    uint96 subId = 0;
    uint allowanceAmount = 500e18;

    // sign signature to approve asset allowance + subId for 500 each
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    assetAllowances[0] = IAllowances.AssetAllowance(usdcAsset, 0, allowanceAmount);
    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](1);
    subIdAllowances[0] = IAllowances.SubIdAllowance(usdcAsset, subId, 0, allowanceAmount);

    IAllowances.PermitAllowance memory permit = IAllowances.PermitAllowance({
      delegate: bob, //
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);

    // bob send transfer to send money to himself!
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: accountId,
      toAcc: bobAcc,
      asset: usdcAsset,
      subId: subId,
      amount: 1000e18,
      assetData: bytes32(0)
    });

    int bobUsdcBefore = subAccounts.getBalance(bobAcc, usdcAsset, subId);

    vm.startPrank(bob);
    subAccounts.permitAndSubmitTransfer(transfer, "", permit, sig);

    int bobUsdcAfter = subAccounts.getBalance(bobAcc, usdcAsset, subId);

    assertEq(bobUsdcAfter - bobUsdcBefore, 1000e18);

    // allowance is consumed immediately
    assertEq(subAccounts.positiveAssetAllowance(accountId, pkOwner, usdcAsset, bob), 0);
    assertEq(subAccounts.negativeAssetAllowance(accountId, pkOwner, usdcAsset, bob), 0);
  }

  function testBatchedPermitAndTransfers() public {
    uint tradeAmount = 1000e18;

    // deposit 1000 USDC to "accountId"
    mintAndDeposit(alice, accountId, usdc, usdcAsset, 0, tradeAmount);

    // depost 1000 coolToken for account2
    mintAndDeposit(alice, accountId2, coolToken, coolAsset, tokenSubId, tradeAmount);

    // permits and signature arrays
    IAllowances.PermitAllowance[] memory permits = new IAllowances.PermitAllowance[](2);
    bytes[] memory signatures = new bytes[](2);

    address orderbook = address(0xb00c);

    // owner1:  sign to approve asset allowance for USDC
    permits[0] = _getAssetPermitUSDC(accountId, orderbook, 1, 0, tradeAmount);
    signatures[0] = _signPermit(privateKey, permits[0]);

    // owner2: sign to approve asset allowance for coolAsset
    IAllowances.AssetAllowance[] memory assetAllowances2 = new IAllowances.AssetAllowance[](1);
    assetAllowances2[0] = IAllowances.AssetAllowance(coolAsset, 0, tradeAmount);
    permits[1] = IAllowances.PermitAllowance({
      delegate: orderbook, // approve orderbook
      nonce: 1,
      accountId: accountId2,
      deadline: block.timestamp,
      assetAllowances: assetAllowances2,
      subIdAllowances: new IAllowances.SubIdAllowance[](0)
    });
    signatures[1] = _signPermit(privateKey2, permits[1]);

    // orderbook will submit a trade to exchange USDC <> CoolToken
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
    transferBatch[0] = ISubAccounts.AssetTransfer({
      fromAcc: accountId,
      toAcc: accountId2,
      asset: IAsset(usdcAsset),
      subId: 0,
      amount: int(tradeAmount),
      assetData: bytes32(0)
    });
    transferBatch[1] = ISubAccounts.AssetTransfer({
      fromAcc: accountId2,
      toAcc: accountId,
      asset: IAsset(coolAsset),
      subId: tokenSubId,
      amount: int(tradeAmount),
      assetData: bytes32(0)
    });

    int acc1UsdBefore = subAccounts.getBalance(accountId, usdcAsset, 0);
    int acc1CoolBefore = subAccounts.getBalance(accountId, coolAsset, tokenSubId);
    int acc2UsdBefore = subAccounts.getBalance(accountId2, usdcAsset, 0);
    int acc2CoolBefore = subAccounts.getBalance(accountId2, coolAsset, tokenSubId);

    vm.prank(orderbook);
    subAccounts.permitAndSubmitTransfers(transferBatch, "", permits, signatures);

    // allowance is consumed immediately
    assertEq(subAccounts.negativeAssetAllowance(accountId, pkOwner, usdcAsset, orderbook), 0);
    assertEq(subAccounts.negativeAssetAllowance(accountId2, pkOwner2, coolAsset, orderbook), 0);

    int acc1UsdAfter = subAccounts.getBalance(accountId, usdcAsset, 0);
    int acc1CoolAfter = subAccounts.getBalance(accountId, coolAsset, tokenSubId);
    int acc2UsdAfter = subAccounts.getBalance(accountId2, usdcAsset, 0);
    int acc2CoolAfter = subAccounts.getBalance(accountId2, coolAsset, tokenSubId);

    // make sure trades went through
    assertEq(acc1UsdBefore - acc1UsdAfter, 1000e18);
    assertEq(acc1CoolAfter - acc1CoolBefore, 1000e18);

    assertEq(acc2UsdAfter - acc2UsdBefore, 1000e18);
    assertEq(acc2CoolBefore - acc2CoolAfter, 1000e18);
  }

  function testDomainSeparator() public view {
    // just for coverage for now
    subAccounts.domainSeparator();
  }

  function _getAssetPermitUSDC(uint _accountId, address spender, uint nonce, uint _positiveAmount, uint _negativeAmount)
    internal
    view
    returns (IAllowances.PermitAllowance memory)
  {
    IAllowances.AssetAllowance[] memory assetAllowances = new IAllowances.AssetAllowance[](1);
    IAllowances.SubIdAllowance[] memory subIdAllowances = new IAllowances.SubIdAllowance[](0);
    assetAllowances[0] = IAllowances.AssetAllowance(usdcAsset, _positiveAmount, _negativeAmount);

    IAllowances.PermitAllowance memory permit = IAllowances.PermitAllowance({
      delegate: spender,
      nonce: nonce,
      accountId: _accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    return permit;
  }

  function _signPermit(uint pk, IAllowances.PermitAllowance memory permit) internal view returns (bytes memory) {
    bytes32 structHash = PermitAllowanceLib.hash(permit);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, MessageHashUtils.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
