# Account

Account contract is a permissionless ERC721 contract that can be used by any protocol to handle their "account management" logic.

There are two at least 2 interfaces you need to implement to comply with `Account.sol`. `IAsset` and `IManager`.

## Accounting

Each account can hold multiple `Assets` with a balance. The base layer stored each `{asset, subId}` as 1 `HeldAsset` structure. The variable `subId` is a identifier that can be used to separate different type of asset under a single **Token** contract. For example, `OptionToken` might use this field to separate options with different strike price, expiry ...etc.

We use an array to record all non-zero `HeldAsset` for an account. The actual balances are stored as `BalanceAndOrder` in a mapping, and we use the `.order` field which stores the index of an asset in the `heldAsset` array to easily remove assets from the `heldAsset` array when the balance is 0.

## Access Control

The most important role for `Account` is to implement the access control, and abstract all the remaining logic to each **Asset** or **Manager** contract.

Based on each asset, they might require approvals differently based on it's **increasing** or **decreasing** balance. Each `Asset` communicates this to `Account` in the asset hook: when an asset is transferred, each asset determines if this balance change needs "allowance" (For example increasing USD balance would not need allowance). If so, `Account` will check the `msg.sender` is properly authorized by the ERC721 owner.

You can think of the access control as a 2 layer approve system:

### First Layer: **ERC721 approval**:

Same as any ERC721 based contract, the approved address is authorized to do anything on the users' behalf. We also grant the **account manager** the ERC721 owner approval that cannot be revoked.

### Second Layer: Custom approval

If `msg.sender` is not the owner of ERC721 approved, it will need **custom approval** to spend an account's money. You can specify the spender to only increase or decrease the balance on a certain asset (or subId).

The logics of custom approval are defined in `Allowance.sol`.

## Trasnsfer Hooks

There are three different flows that could update an account's balance:

![Base layer](./imgs/overall/base-layer-basic.png)

### 1. Normal transactions

Transactions initiated by users or third party contracts need to pass the information to **Asset** through `IAsset.handleAdjustment` to get the final balance and access requirements, and pass to **Manager** through `IManager.handleAdjustment` to determine if the final state of the account is valid.

These transactions should be initiated through `submitTransfer` or `submitTransfers` functions.

### 2. Transactions initiated by managers

Transactions initiated by the manager don't have to go through manager hook again at the end, but will still go through `IAsset.handleAdjustment`.

These transactions should be initiated through `managerAdjustment`.

*note: managers can also update the balance through `submitTransfers`, but it will trigger itself with `IManager.handleAdjustment` at the end.

### 3. Transactions initiated by assets

Transactions initiated by assets can choose whether it needs to go through its own asset hook during balance update (base on implementation, sometimes `handleAdjustment` can be handy to update interest rate ...etc, so routing everything through the hook might not be a bad idea), but all transfers must still go through `IManager.handleAdjustment` at then end.

These transactions should be initiated through `assetAdjustment`.
