// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "src/interfaces/AccountStructs.sol";

import "../mocks/assets/OptionToken.sol";
import "../mocks/assets/BaseWrapper.sol";
import "../mocks/assets/QuoteWrapper.sol";
import "../mocks/assets/lending/Lending.sol";
import "../mocks/assets/lending/ContinuousJumpRateModel.sol";
import "../mocks/assets/lending/InterestRateModel.sol";
import "../mocks/managers/DumbManager.sol";

import "../../shared/mocks/MockAsset.sol";
import "../../shared/mocks/MockERC20.sol";

contract AccountGasScript is Script {
  uint ownAcc;
  Account account;
  MockERC20 usdc;
  MockERC20 dai;
  MockAsset usdcAdapter;
  MockAsset optionAdapter;
  DumbManager manager;

  uint expiry;

  function run() external {
    vm.startBroadcast();

    deployMockSystem();

    setupAccounts(500);

    // gas tests

    _gasSingleTransferUSDC();

    // bulk transfer gas cost
    _gasBulkTransferUSDC(10);
    _gasBulkTransferUSDC(20);
    _gasBulkTransferUSDC(100);

    _gasSingleTradeUSDCWithOption();

    // buck trade single account with multiple accounts
    _gasBulkTradeUSDCWithDiffOption(10);
    _gasBulkTradeUSDCWithDiffOption(20);

    // test spliting a 600x account
    _gasBulkSplitPosition(10);
    _gasBulkSplitPosition(20);

    // test settlement: the EOA already have 600 assets
    // _setExpiryPrice();

    // _gasSettleAccountWithMultiplePositions(100);
    // _gasSettleAccountWithMultiplePositions(500);

    vm.stopBroadcast();
  }

  function _gasSingleTransferUSDC() public {
    // setup: not counting gas
    uint amount = 50e18;
    AccountStructs.AssetTransfer memory transfer = AccountStructs.AssetTransfer({
      fromAcc: ownAcc,
      toAcc: 2,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(amount),
      assetData: bytes32(0)
    });

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfer(transfer, "");
    uint endGas = gasleft();

    console.log("gas:SingleTransferUSDC:", initGas - endGas);
  }

  function _gasBulkTransferUSDC(uint counts) public {
    // setup: not counting gas
    uint amount = 50e18;
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](counts);

    // in each round we use fresh from and to. So we test the worst cases when none of the storage is warmed
    for (uint i = 0; i < counts;) {
      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: 2 * i + 1,
        toAcc: 2 * i + 2,
        asset: IAsset(usdcAdapter),
        subId: 0,
        amount: int(amount),
        assetData: bytes32(0)
      });
      unchecked {
        i++;
      }
    }

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:BulkTransferUSDC(", counts, "):", initGas - endGas);
  }

  function _gasSingleTradeUSDCWithOption() public {
    uint amount = 50e18;
    uint usdcAmount = 300e18;
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](2);

    uint subId = block.timestamp;

    transferBatch[0] = AccountStructs.AssetTransfer({ // short option and give it to another person
      fromAcc: ownAcc,
      toAcc: 2,
      asset: IAsset(optionAdapter),
      subId: subId,
      amount: int(amount),
      assetData: bytes32(0)
    });
    transferBatch[1] = AccountStructs.AssetTransfer({ // premium
      fromAcc: 2,
      toAcc: ownAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(usdcAmount),
      assetData: bytes32(0)
    });

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:SingleTradeUSDCWithOption:", initGas - endGas);
  }

  function _gasBulkTradeUSDCWithDiffOption(uint counts) public {
    // Gas test for a singel account to trade with 500 different accounts on different asset
    // which will ends up having counts+1 assets in the heldAsset array.

    // setup: not counting gas
    uint amount = 50e18;
    uint usdcAmount = 300e18;
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](
      counts * 2
    );

    for (uint i = 0; i < counts;) {
      uint subId = 1000e18 + (i * 10e18);

      transferBatch[2 * i] = AccountStructs.AssetTransfer({ // short option and give it to another person
        fromAcc: ownAcc,
        toAcc: i + 2, // account 1 is the EOA. start from 2
        asset: IAsset(optionAdapter),
        subId: subId,
        amount: int(amount),
        assetData: bytes32(0)
      });
      transferBatch[2 * i + 1] = AccountStructs.AssetTransfer({ // premium
        fromAcc: i + 2,
        toAcc: ownAcc,
        asset: IAsset(usdcAdapter),
        subId: 0,
        amount: int(usdcAmount),
        assetData: bytes32(0)
      });
      unchecked {
        i++;
      }
    }

    // estimate tx cost
    uint initGas = gasleft();
    account.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:BulkTradeUSDCWithDiffOption(", counts, "):", initGas - endGas);
  }

  function _gasBulkSplitPosition(uint counts) public {
    AccountStructs.AssetBalance[] memory balances = account.getAccountBalances(ownAcc);

    if (counts > balances.length + 1) {
      revert("don't have this many asset to settle");
    }

    // select bunch of assets to settle
    AccountStructs.AssetTransfer[] memory transferBatch = new AccountStructs.AssetTransfer[](counts);

    for (uint i = 0; i < counts;) {
      transferBatch[i] = AccountStructs.AssetTransfer({
        fromAcc: ownAcc,
        toAcc: i + 2, // account 1 is the EOA. start from 2
        asset: IAsset(optionAdapter),
        subId: uint96(balances[i + 1].subId),
        amount: (balances[i + 1].balance) / 2, // send half to another account
        assetData: bytes32(0)
      });
      unchecked {
        i++;
      }
    }

    uint initGas = gasleft();
    account.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:BulkSplitPosition(", counts, "):", initGas - endGas);
  }

  // function _gasSettleAccountWithMultiplePositions(uint counts) public {
  //   AccountStructs.AssetBalance[] memory balances = account.getAccountBalances(ownAcc);

  //   if (counts > balances.length + 1) revert("don't have this many asset to settle");

  //   // select bunch of assets to settle
  //   AccountStructs.HeldAsset[] memory assets = new AccountStructs.HeldAsset[](counts);
  //   for (uint i; i < counts; i ++) {
  //     assets[i] = AccountStructs.HeldAsset({
  //       asset: IAsset(address(optionAdapter)),
  //       subId: uint96(balances[i+1].subId)
  //     });
  //   }
  //   uint initGas = gasleft();
  //   rm.settleAssets(ownAcc, assets);
  //   uint endGas = gasleft();

  //   console.log("gas:SettleAccountWithMultiplePositions(", counts, "):", initGas - endGas);

  //   // AccountStructs.AssetBalance[] memory balancesAfter = account.getAccountBalances(ownAcc);
  //   // console.log("\t - asset left:", balancesAfter.length);
  // }

  /// @dev deploy mock system
  function deployMockSystem() public {
    /* Base Layer */
    account = new Account("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");

    // usdc asset: deposit with usdc, cannot be negative
    usdcAdapter = new MockAsset(IERC20(usdc), IAccount(address(account)), false);

    // optionAsset: not allow deposit, can be negative
    optionAdapter = new MockAsset(IERC20(address(0)), IAccount(address(account)), true);

    /* Risk Manager */
    manager = new DumbManager(address(account));
  }

  function setupAccounts(uint amount) public {
    // create 1 account for EOA
    ownAcc = account.createAccount(msg.sender, IManager(address(manager)));
    usdc.mint(msg.sender, 1000_000_000e18);
    usdc.approve(address(usdcAdapter), type(uint).max);
    usdcAdapter.deposit(ownAcc, 0, 100_000_000e18);
    // create bunch of accounts and send to everyone
    for (uint160 i = 1; i <= amount; i++) {
      address owner = address(i);
      uint acc = account.createAccountWithApproval(owner, msg.sender, IManager(address(manager)));

      // deposit usdc for each account
      usdcAdapter.deposit(acc, 0, 1_000e18);
    }

    expiry = block.timestamp + 1 days;
  }
}
