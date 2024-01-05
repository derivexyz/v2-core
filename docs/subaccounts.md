# SubAccounts

The `SubAccounts` contract is a permissionless ERC721 contract that can be used by any protocol to (1) handle the accounting of asset balances, (2) access control, and (3) enforce proper `Asset` and `Manager` interactions whenever balance adjustments are made.

There are at least two interfaces you need to implement to comply with `SubAccounts.sol`: `IAsset` and `IManager`.

## Accounting

Each account can hold a balance per `Assets` / `subId` pair, where `subId` is an identifier used to distinguish different asset sub-types codified by the same asset contract (e.g., $1500 Jan 1st ETH Call vs $1600 Jan 1st ETH Call).

The base layer also tracks `{ asset, subId }` pairs with non-zero balances in a `heldAssets` array per account. The actual balances are stored as `BalanceAndOrder` structs in a mapping, and we use the `.order` field to store the index of the `{ asset / subId }` in the `heldAssets` array to efficiently remove assets from the `heldAsset` array when the balance returns to 0.

## Access Control

Each asset can set unique approval requirements depending on whether the balance is **increasing** or **decreasing**. When an asset is transferred, each asset determines if this balance change requires an "allowance." For example, an **increasing** USD balance would not require an allowance, while a **decreasing** balance would. Conversely, if the asset is a perpetual, both **decreasing** and **increasing** adjustments would require an allowance, as a positive perp balance could have a funding rate.

You can think of the access control as a two-layer approval system:

### First Layer: **ERC721 Approval**

Similar to any ERC721-based contract, the owner or an ERC721-approved address is authorized to do anything on the user's behalf. We also grant irrevocable approval by default to the **manager** of the account.

### Second Layer: Custom Approval

If `msg.sender` is not the owner or ERC721-approved, they will need **custom approval** to spend the account's balance. You can specify the spender to only increase or decrease the balance on a certain asset (or subId).

The logic for custom approvals is defined in `Allowance.sol`.

## Updating Subaccounts

There are three different flows that could update an account's balance. Each flow has a unique structure for how the `Asset` and `Manager` must be engaged for the flow to succeed.

![Base layer](./imgs/overall/base-layer-basic.png)

### 1. Symmetric Transactions

Transfers that subtract amount `x` from one account and add amount `x` to another account can be initiated by anyone using `Account.submitTransfers`. During the transfer, `SubAccounts.sol` passes information (the caller, old balance, transfer amount, etc.) to the **Asset** through `IAsset.handleAdjustment`. In return, the asset returns the final balance and access requirements. This is called the `asset hook`.

`SubAccounts.sol` also passes relevant information (the caller, accountId) to the **Manager** through `IManager.handleAdjustment` to determine if the final state of the account is valid. This is called the `manager hook`.

### 2. Adjustments Initiated by Managers

Adjustments initiated by the manager bypass the `manager hook`, but still go through `IAsset.handleAdjustment`. These transactions are initiated through `Account.managerAdjustment`. For example, managers could use this functionality to transfer cash between accounts upon option settlement. 

*Note: Managers can also update the balance through `submitTransfers`, but it will trigger itself with `IManager.handleAdjustment` at the end.

### 3. Adjustments Initiated by Assets

An asset can choose to go through its own `asset hook` during a self-triggered adjustment via `Account.assetAdjustment` (e.g., `handleAdjustment` can be handy to update interest rate accruals, so routing everything through the hook might not be a bad idea), but all transfers must still go through `IManager.handleAdjustment` at the end of the transaction.

One key feature that this enables is deposits and withdrawals of ETH or USD to form wrapped representations of these assets in the account layer.
