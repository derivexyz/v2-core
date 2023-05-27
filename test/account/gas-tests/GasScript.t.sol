// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Script.sol";

import "../mocks/assets/OptionToken.sol";
import "../mocks/assets/BaseWrapper.sol";
import "../mocks/assets/QuoteWrapper.sol";
import "../mocks/assets/lending/InterestRateModel.sol";
import "../mocks/managers/DumbManager.sol";

import "../../shared/mocks/MockERC20.sol";
import "../../shared/mocks/MockAsset.sol";

contract AccountGasScript is Script {
  uint ownAcc;
  SubAccounts subAccounts;
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

    // trade multiple "option token" between 2 accounts
    _gasTradeMultipleOptions(10); // 2 parties exchange 10 positions
    _gasTradeMultipleOptions(20);
    _gasTradeMultipleOptions(100);

    // test spliting multiple balances to another accounts
    _gasBulkSplitPosition(10);
    _gasBulkSplitPosition(20);
    _gasBulkSplitPosition(50);

    // estimate gas cost on bulk settlement (setting balance to 0)
    _gasClearAccountBalances(10);
    _gasClearAccountBalances(20);
    _gasClearAccountBalances(50);

    vm.stopBroadcast();
  }

  function _gasSingleTransferUSDC() public {
    // setup: not counting gas
    uint amount = 50e18;
    ISubAccounts.AssetTransfer memory transfer = ISubAccounts.AssetTransfer({
      fromAcc: ownAcc,
      toAcc: 2,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(amount),
      assetData: bytes32(0)
    });

    // estimate tx cost
    uint initGas = gasleft();
    subAccounts.submitTransfer(transfer, "");
    uint endGas = gasleft();

    console.log("gas:SingleTransferUSDC:", initGas - endGas);
  }

  function _gasBulkTransferUSDC(uint counts) public {
    // setup: not counting gas
    uint amount = 50e18;
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](counts);

    // in each round we use fresh from and to. So we test the worst cases when none of the storage is warmed
    for (uint i = 0; i < counts;) {
      transferBatch[i] = ISubAccounts.AssetTransfer({
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
    subAccounts.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:BulkTransferUSDC(", counts, "):", initGas - endGas);
  }

  function _gasSingleTradeUSDCWithOption() public {
    uint amount = 50e18;
    uint usdcAmount = 300e18;
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](2);

    uint subId = block.timestamp;

    transferBatch[0] = ISubAccounts.AssetTransfer({ // short option and give it to another person
      fromAcc: ownAcc,
      toAcc: 2,
      asset: IAsset(optionAdapter),
      subId: subId,
      amount: int(amount),
      assetData: bytes32(0)
    });
    transferBatch[1] = ISubAccounts.AssetTransfer({ // premium
      fromAcc: 2,
      toAcc: ownAcc,
      asset: IAsset(usdcAdapter),
      subId: 0,
      amount: int(usdcAmount),
      assetData: bytes32(0)
    });

    // estimate tx cost
    uint initGas = gasleft();
    subAccounts.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:SingleTradeUSDCWithOption:", initGas - endGas);
  }

  function _gasTradeMultipleOptions(uint counts) public {
    // Gas test for 2 accounts to exchange multiple asset balances

    // setup: not counting gas
    uint amount = 50e18;
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](counts);

    uint fromAcc = 1;
    uint toAcc = 2;

    for (uint i = 0; i < counts;) {
      uint subId = i + 100;

      transferBatch[i] = ISubAccounts.AssetTransfer({ // short option and give it to another person
        fromAcc: fromAcc,
        toAcc: toAcc, // account 1 is the EOA. start from 2
        asset: IAsset(optionAdapter),
        subId: subId,
        amount: int(amount),
        assetData: bytes32(0)
      });
      unchecked {
        i++;
      }
    }

    // estimate tx cost
    uint initGas = gasleft();
    subAccounts.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:TradeMultipleOptions(", counts, "):", initGas - endGas);
  }

  function _gasBulkSplitPosition(uint counts) public {
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(ownAcc);

    if (counts > balances.length + 1) {
      revert("don't have this many asset to settle");
    }

    // select bunch of assets to settle
    ISubAccounts.AssetTransfer[] memory transferBatch = new ISubAccounts.AssetTransfer[](counts);

    for (uint i = 0; i < counts;) {
      transferBatch[i] = ISubAccounts.AssetTransfer({
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
    subAccounts.submitTransfers(transferBatch, "");
    uint endGas = gasleft();

    console.log("gas:BulkSplitPosition(", counts, "):", initGas - endGas);
  }

  function _gasClearAccountBalances(uint counts) public {
    ISubAccounts.AssetBalance[] memory balances = subAccounts.getAccountBalances(ownAcc);

    if (counts > balances.length + 1) revert("don't have this many asset to settle");

    // select bunch of assets to settle
    ISubAccounts.HeldAsset[] memory assets = new ISubAccounts.HeldAsset[](counts);
    for (uint i; i < counts; i++) {
      assets[i] = ISubAccounts.HeldAsset({asset: IAsset(address(optionAdapter)), subId: uint96(balances[i + 1].subId)});
    }
    uint initGas = gasleft();
    manager.clearBalances(ownAcc, assets);
    uint endGas = gasleft();

    console.log("gas:ClearAccountBalances(", counts, "):", initGas - endGas);

    // ISubAccounts.AssetBalance[] memory balancesAfter = subAccounts.getAccountBalances(ownAcc);
    // console.log("\t - asset left:", balancesAfter.length);
  }

  /// @dev deploy mock system
  function deployMockSystem() public {
    /* Base Layer */
    subAccounts = new SubAccounts("Lyra Margin Accounts", "LyraMarginNFTs");

    /* Wrappers */
    usdc = new MockERC20("usdc", "USDC");

    // usdc asset: deposit with usdc, cannot be negative
    usdcAdapter = new MockAsset(IERC20(usdc), subAccounts, false);

    // optionAsset: not allow deposit, can be negative
    optionAdapter = new MockAsset(IERC20(address(0)), subAccounts, true);

    /* Risk Manager */
    manager = new DumbManager(address(subAccounts));
  }

  function setupAccounts(uint amount) public {
    // create 1 account for EOA
    ownAcc = subAccounts.createAccount(msg.sender, IManager(address(manager)));
    usdc.mint(msg.sender, 1000_000_000e18);
    usdc.approve(address(usdcAdapter), type(uint).max);
    usdcAdapter.deposit(ownAcc, 0, 100_000_000e18);
    // create bunch of accounts and send to everyone
    for (uint160 i = 1; i <= amount; i++) {
      address owner = address(i);
      uint acc = subAccounts.createAccountWithApproval(owner, msg.sender, IManager(address(manager)));

      // deposit usdc for each account
      usdcAdapter.deposit(acc, 0, 1_000e18);
    }

    expiry = block.timestamp + 1 days;
  }

  // add in a function prefixed with test here to prevent coverage from picking it up.
  function test() public {}
}
