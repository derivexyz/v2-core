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

contract UNIT_AccountPermit is Test {
  uint private immutable privateKey;
  address private immutable pkOwner;
  bytes32 public domainSeparator;

  IAsset asset = IAsset(address(0x8888));

  address public alice;
  address public bob;

  Account account;
  MockManager dumbManager;

  uint accountId;
  uint positiveAmount = 1e18;
  uint negativeAmount = 2e18;

  constructor() {
    privateKey = 0xBEEF;
    pkOwner = vm.addr(privateKey);
  }

  function setUp() public {
    alice = address(0xaa);
    bob = address(0xbb);

    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    domainSeparator = account.domainSeparator();

    dumbManager = new MockManager(address(account));

    // get a account for pkOwner
    accountId = account.createAccount(pkOwner, dumbManager);
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
    assetAllowances[0] = AccountStructs.AssetAllowance(asset, positiveAmount, negativeAmount);
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

    assertEq(account.positiveAssetAllowance(accountId, pkOwner, asset, alice), positiveAmount);
    assertEq(account.negativeAssetAllowance(accountId, pkOwner, asset, alice), negativeAmount);
  }

  function testPermitCanUpdateSubIdAllowance() public {
    uint96 subId = 1;
    uint nonce = 1;
    AccountStructs.AssetAllowance[] memory assetAllowances = new AccountStructs.AssetAllowance[](0);
    AccountStructs.SubIdAllowance[] memory subIdAllowances = new AccountStructs.SubIdAllowance[](1);
    subIdAllowances[0] = AccountStructs.SubIdAllowance(asset, subId, positiveAmount, negativeAmount);

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

    assertEq(account.positiveSubIdAllowance(accountId, pkOwner, asset, subId, alice), positiveAmount);
    assertEq(account.negativeSubIdAllowance(accountId, pkOwner, asset, subId, alice), negativeAmount);
  }

  function _signPermit(uint pk, AccountStructs.PermitAllowance memory permit) internal view returns (bytes memory) {
    bytes32 structHash = PermitAllowanceLib.hash(permit);
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(domainSeparator, structHash));
    return bytes.concat(r, s, bytes1(v));
  }
}
