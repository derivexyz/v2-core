// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../../../src/Account.sol";

import "../../mocks/TestERC20.sol";
import "../../mocks/assets/DumbAsset.sol";
import "../../mocks/managers/DumbManager.sol";
import "forge-std/Test.sol";

contract AccountTestBase is Test {
    address alice;
    address bob;

    uint256 aliceAcc;
    uint256 bobAcc;

    DumbManager dumbManager;

    TestERC20 usdc;
    TestERC20 coolToken;

    DumbAsset usdcAsset;
    DumbAsset coolAsset;

    Account account;

    uint tokenSubId = 1000;

    function setUpAccounts() public {
        alice = address(0xaa);
        bob = address(0xbb);

        account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

        /* mock tokens that can be deposited into accounts */
        usdc = new TestERC20("USDC", "USDC");
        usdcAsset = new DumbAsset(IERC20(usdc), account, false);

        coolToken = new TestERC20("Cool", "COOL");
        coolAsset = new DumbAsset(IERC20(coolToken), account, false);

        dumbManager = new DumbManager(address(account));

        aliceAcc = account.createAccount(alice, dumbManager);
        bobAcc = account.createAccount(bob, dumbManager);

        // give Alice usdc, and give Bob coolToken
        mintAndDeposit(
            alice,
            aliceAcc,
            usdc,
            usdcAsset,
            0,
            10000000e18
        );
        mintAndDeposit(
            bob,
            bobAcc,
            coolToken,
            coolAsset,
            tokenSubId,
            10000000e18
        );
    }

    function mintAndDeposit(
        address user,
        uint256 accountId,
        TestERC20 token,
        DumbAsset assetWrapper,
        uint256 subId,
        uint256 amount
    ) public {
        token.mint(user, amount);

        vm.startPrank(user);
        token.approve(address(assetWrapper), type(uint256).max);
        assetWrapper.deposit(accountId, subId, amount);
        vm.stopPrank();
    }

    function tradeTokens(
        uint256 fromAcc,
        uint256 toAcc,
        address assetA,
        address assetB,
        uint256 tokenAAmounts,
        uint256 tokenBAmounts,
        uint256 tokenASubId,
        uint256 tokenBSubId
    ) internal {
        IAccount.AssetTransfer memory tokenATransfer = IAccount.AssetTransfer({
            fromAcc: fromAcc,
            toAcc: toAcc,
            asset: IAsset(assetA),
            subId: tokenASubId,
            amount: int256(tokenAAmounts),
            assetData: bytes32(0)
        });

        IAccount.AssetTransfer memory tokenBTranser = IAccount.AssetTransfer({
            fromAcc: toAcc,
            toAcc: fromAcc,
            asset: IAsset(assetB),
            subId: tokenBSubId,
            amount: int256(tokenBAmounts),
            assetData: bytes32(0)
        });

        IAccount.AssetTransfer[]
            memory transferBatch = new IAccount.AssetTransfer[](2);
        transferBatch[0] = tokenATransfer;
        transferBatch[1] = tokenBTranser;

        account.submitTransfers(transferBatch, "");
    }

    function transferToken(
        uint256 fromAcc,
        uint256 toAcc,
        IAsset asset,
        uint256 subId,
        int256 tokenAmounts
    ) internal {
        IAccount.AssetTransfer memory transfer = IAccount.AssetTransfer({
            fromAcc: fromAcc,
            toAcc: toAcc,
            asset: asset,
            subId: subId,
            amount: int256(tokenAmounts),
            assetData: bytes32(0)
        });

        account.submitTransfer(transfer, "");
    }
}
