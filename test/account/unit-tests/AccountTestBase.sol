// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/Accounts.sol";

import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockManager.sol";
import "forge-std/Test.sol";

contract AccountTestBase is Test {
  address alice;
  address bob;

  uint aliceAcc;
  uint bobAcc;

  MockManager dumbManager;

  MockERC20 usdc;
  MockERC20 coolToken;

  MockAsset usdcAsset;
  MockAsset coolAsset;

  Accounts account;

  uint tokenSubId = 1000;

  function setUpAccounts() public {
    alice = address(0xaa);
    bob = address(0xbb);

    account = new Accounts("Lyra Margin Accounts", "LyraMarginNFTs");

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");
    usdcAsset = new MockAsset(IERC20(usdc), IAccounts(address(account)), false);

    coolToken = new MockERC20("Cool", "COOL");
    coolAsset = new MockAsset(IERC20(coolToken), IAccounts(address(account)), false);

    dumbManager = new MockManager(address(account));

    aliceAcc = account.createAccount(alice, dumbManager);
    bobAcc = account.createAccount(bob, dumbManager);

    // give Alice usdc, and give Bob coolToken
    mintAndDeposit(alice, aliceAcc, usdc, usdcAsset, 0, 10000000e18);
    mintAndDeposit(bob, bobAcc, coolToken, coolAsset, tokenSubId, 10000000e18);
  }

  function mintAndDeposit(
    address user,
    uint accountId,
    MockERC20 token,
    MockAsset assetWrapper,
    uint subId,
    uint amount
  ) public {
    token.mint(user, amount);

    vm.startPrank(user);
    token.approve(address(assetWrapper), type(uint).max);
    assetWrapper.deposit(accountId, subId, amount);
    vm.stopPrank();
  }

  function tradeTokens(
    uint fromAcc,
    uint toAcc,
    address assetA,
    address assetB,
    uint tokenAAmounts,
    uint tokenBAmounts,
    uint tokenASubId,
    uint tokenBSubId
  ) internal {
    AccountStructs.AssetTransfer memory tokenATransfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(assetA),
      subId: tokenASubId,
      amount: int(tokenAAmounts),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer memory tokenBTranser = AccountStructs.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: IAsset(assetB),
      subId: tokenBSubId,
      amount: int(tokenBAmounts),
      assetData: bytes32(0)
    });

    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);
    transferBatch[0] = tokenATransfer;
    transferBatch[1] = tokenBTranser;

    account.submitTransfers(transferBatch, "");
  }

  function transferToken(uint fromAcc, uint toAcc, IAsset asset, uint subId, int tokenAmounts) internal {
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: asset,
      subId: subId,
      amount: int(tokenAmounts),
      assetData: bytes32(0)
    });

    account.submitTransfer(transfer, "");
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
