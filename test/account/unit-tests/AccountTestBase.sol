// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "../../../src/SubAccounts.sol";

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

  SubAccounts subAccounts;

  uint tokenSubId = 1000;

  function setUpAccounts() public {
    alice = address(0xaa);
    bob = address(0xbb);

    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    /* mock tokens that can be deposited into accounts */
    usdc = new MockERC20("USDC", "USDC");
    usdcAsset = new MockAsset(IERC20(usdc), ISubAccounts(address(subAccounts)), false);

    coolToken = new MockERC20("Cool", "COOL");
    coolAsset = new MockAsset(IERC20(coolToken), ISubAccounts(address(subAccounts)), false);

    dumbManager = new MockManager(address(subAccounts));

    aliceAcc = subAccounts.createAccount(alice, dumbManager);
    bobAcc = subAccounts.createAccount(bob, dumbManager);

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
    ISubAccounts.AssetTransfer memory tokenATransfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: IAsset(assetA),
      subId: tokenASubId,
      amount: int(tokenAAmounts),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer memory tokenBTranser = ISubAccounts.AssetTransfer({
      fromAcc: toAcc,
      toAcc: fromAcc,
      asset: IAsset(assetB),
      subId: tokenBSubId,
      amount: int(tokenBAmounts),
      assetData: bytes32(0)
    });

    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);
    transferBatch[0] = tokenATransfer;
    transferBatch[1] = tokenBTranser;

    subAccounts.submitTransfers(transferBatch, "");
  }

  function transferToken(uint fromAcc, uint toAcc, IAsset asset, uint subId, int tokenAmounts) internal {
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: fromAcc,
      toAcc: toAcc,
      asset: asset,
      subId: subId,
      amount: int(tokenAmounts),
      assetData: bytes32(0)
    });

    subAccounts.submitTransfer(transfer, "");
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
