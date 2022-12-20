// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

import "openzeppelin/utils/cryptography/ECDSA.sol";

import "../../../src/Account.sol";
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

    domainSeparator = account.domainSeparator();

    // get a account for pkOwner
    accountId = account.createAccount(pkOwner, dumbManager);

    accountId2 = account.createAccount(pkOwner2, dumbManager);
  }

  function testPermitCannotPermitWithExpiredSignature() public {
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](0);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](0);

    AccountStructs.PermitAllowance memory permit = AccountStructs.PermitAllowance({
      delegate: alice,
      nonce: 0,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    vm.warp(block.timestamp + 10);

    bytes memory sig = _signPermit(privateKey, permit);

    vm.expectRevert(Account.AC_SignatureExpired.selector);
    account.permit(permit, sig);
  }

  function testPermitCannotPermitWithFakeSignature() public {
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](0);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](0);
    AccountStructs.PermitAllowance memory permit = AccountStructs.PermitAllowance({
      delegate: alice,
      nonce: 0,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    // use a bad private key to sign
    bytes memory sig = _signPermit(0x0fac, permit);

    vm.expectRevert(Account.AC_InvalidPermitSignature.selector);
    account.permit(permit, sig);
  }

  function testPermitCanUpdateAssetAllowance() public {
    uint nonce = 1;
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance(usdcAsset, positiveAmount, negativeAmount);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](0);

    AccountStructs.PermitAllowance memory permit = AccountStructs.PermitAllowance({
      delegate: alice,
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);
    account.permit(permit, sig);

    assertEq(account.positiveAssetAllowance(accountId, pkOwner, usdcAsset, alice), positiveAmount);
    assertEq(account.negativeAssetAllowance(accountId, pkOwner, usdcAsset, alice), negativeAmount);
  }

  function testPermitCanUpdateSubIdAllowance() public {
    uint96 subId = 0;
    uint nonce = 1;
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](0);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](1);
    subIdAllowances[0] = AccountStructs.SubIdAllowance(usdcAsset, subId, positiveAmount, negativeAmount);

    AccountStructs.PermitAllowance memory permit = AccountStructs.PermitAllowance({
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
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](0);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](1);
    subIdAllowances[0] = AccountStructs.SubIdAllowance(usdcAsset, subId, positiveAmount, negativeAmount);

    AccountStructs.PermitAllowance memory permit = AccountStructs.PermitAllowance({
      delegate: alice,
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);
    // first permit should pass
    account.permit(permit, sig);

    vm.expectRevert(Account.AC_NonceTooLow.selector);
    account.permit(permit, sig);
  }

  function testCannotReplayAttack() public {
    uint96 subId = 0;
    uint nonce = 1;
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](0);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](1);
    subIdAllowances[0] = AccountStructs.SubIdAllowance(usdcAsset, subId, positiveAmount, negativeAmount);

    AccountStructs.PermitAllowance memory permit = AccountStructs.PermitAllowance({
      delegate: alice,
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp + 1,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);

    vm.chainId(31337);

    vm.expectRevert(Account.AC_InvalidPermitSignature.selector);
    account.permit(permit, sig);
  }

  function testPermitAndTransfer() public {
    // deposit 1000 USDC to "accountId"
    mintAndDeposit(alice, accountId, usdc, usdcAsset, 0, 1000e18);

    uint nonce = 5;
    uint96 subId = 0;
    uint allowanceAmount = 500e18;

    // sign signature to approve asset allowance + subId for 500 each
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance(usdcAsset, 0, allowanceAmount);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](1);
    subIdAllowances[0] = AccountStructs.SubIdAllowance(usdcAsset, subId, 0, allowanceAmount);

    AccountStructs.PermitAllowance memory permit = AccountStructs.PermitAllowance({
      delegate: bob, //
      nonce: nonce,
      accountId: accountId,
      deadline: block.timestamp,
      assetAllowances: assetAllowances,
      subIdAllowances: subIdAllowances
    });

    bytes memory sig = _signPermit(privateKey, permit);

    // bob send transfer to send money to himself!
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
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

    // depost 500 coolToken for account2
    mintAndDeposit(alice, accountId2, coolToken, coolAsset, tokenSubId, tradeAmount);

    // premits and signature arrays
    AccountStructs.PermitAllowance[] memory permits = new AccountStructs.PermitAllowance[](2);
    bytes[] memory signatures = new bytes[](2);

    address orderbook = address(0xb00c);

    // owner1:  sign to approve asset allowance for USDC
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](1);
    assetAllowances[0] = AccountStructs.AssetAllowance(usdcAsset, 0, tradeAmount);

    permits[0] = AccountStructs.PermitAllowance({
      delegate: orderbook, // approve orderbook
      nonce: 1,
      accountId: accountId,
      deadline: block.timestamp,
      assetAllowances: assetAllowances,
      subIdAllowances: new AccountStructs.SubIdAllowance[](0)
    });
    signatures[0] = _signPermit(privateKey, permits[0]);

    // owner2: sign to approve asset allowance for coolAsset
    AccountStructs.AssetAllowance[] memory assetAllowances2 = new AccountStructs.AssetAllowance[](1);
    assetAllowances2[0] = AccountStructs.AssetAllowance(coolAsset, tokenSubId, tradeAmount);

    permits[1] = AccountStructs.PermitAllowance({
      delegate: orderbook, // approve orderbook
      nonce: 1,
      accountId: accountId2,
      deadline: block.timestamp,
      assetAllowances: assetAllowances2,
      subIdAllowances: new AccountStructs.SubIdAllowance[](0)
    });
    signatures[1] = _signPermit(privateKey2, permits[1]);

    // orderbook send transfer to send money to himself!
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = AccountStructs.AssetTransfer({
      fromAcc: accountId,
      toAcc: accountId2,
      asset: IAsset(usdcAsset),
      subId: 0,
      amount: int(tradeAmount),
      assetData: bytes32(0)
    });
    transferBatch[1] = AccountStructs.AssetTransfer({
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

  function _signPermit(uint pk, AccountStructs.PermitAllowance memory permit) internal view returns (bytes memory) {
    bytes32 structHash = PermitAllowanceLib.hash(permit);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
