# Assets

At the launch of V2, we have the following assets that can be traded with PMRM or SRM:

* [CashAsset](#cashasset)
* [OptionAsset](#optionasset)
* [PerpAsset](#perpasset)
* [BaseAsset (WrappedERC20Asset)](#baseasset)

The asset contracts are set of contracts that abstract away the logic of asset balance updates, and keep track of information needed for managers to settle if necessary.

## CashAsset

A CashAsset can be introduced into the system by depositing USDC into the `CashAsset` contract. Cash is used as the primary asset for accounting, settlement, and bidding in liquidation.

A user's CashAsset balance can be negative, which means you are "borrowing" cash from the system. If you borrow cash, you need to pay an interest rate to everyone who has a positive balance. The interest rate model is very similar to Aave, and the logic to determine interest rates is abstracted into the InterestRateModel contract.

Both option and perp assets settle in cash too, meaning the manager taking care of settlement can print or burn cash balance into someone's account. This additional printed number is recorded in `netSettledCash`.

Another special thing about CashAsset is that it is in charge of calculating the interest and apply that to the ending balance during the asset hook.

### Withdraw Fee

It is possible that the whole cash system could become insolvent, meaning we have more cash than the `CashAsset` is actually holding. This is only supposed to happen when an "insolvent auction" takes place and the security module doesn't have enough cash to cover the loss.

In that case, to avoid a bank run, we turn on `temporaryWithdrawFeeEnabled`, so users can no longer get 1 USDC with 1 cash. We will also start collecting 100% of interest to the security module and try to recover from insolvency.

## OptionAsset

OptionAsset is currently the only asset that utilizes the subId field, which encodes information about an option position like strike price, expiry, etc.

OptionAsset is one of the simplest assets, it simply allows positive and negative balances: when two parties trade options, one of them goes negative and the other positive, the total amount of unexpired long and short should always be the same.

## PerpAsset

PerpAsset can also have positive or negative positions like options, but it has "funding" and "continuous settlement" which are a bit more complicated.

### Continuous Settlement

Whenever someone trades perp, we settle their outstanding PNL with the current perp market price. This means that if you opened a long perp position when the market price was 1000, the current price is 1500, and you add 0.001 to your position, we settle the $500 into your account first and then record that you "opened a new position with a size of 1.001" at $1500.

Notice that the actual printing part of settlement is taken care of by the manager in the post transfers hook, because all settlement (printing cash) has to come from the manager contract to SubAccounts. When the asset hook is triggered, it only updates an account's PNL into a local storage variable (`positions[accountId]`).

### Funding

The funding is calculated during the asset hook and settled in the post-transfer manager hook, similar to the "settlement" part. Funding is also the part of the perp asset where we use the index price.

## BaseAsset

The base asset is a wrapped version of ERC20, they are just wrappers that allow people to add assets into the system (and be used as collateral). Note that the balance of the BaseAsset cannot be negative.

## Shared Contract: PositionTracking

In order to limit the risk introduced by each "Asset contract", we have all PerpAsset, Option, and `WrappedERC20Asset` inherit a `PositionTracking` contract, that updates the total opened position among all managers during the asset hook. If the cap is reached, the asset cannot be traded anymore (but can be reduced), this is ensured by the manager in the post transfer hook.

## Shared Contract: GlobalSubIdOITracking

For non-whitelisted contracts (outside of our order book), we charge an OI fee if someone increases the open interest (OI) of perp or option. This is to ensure people cannot pose risk to the overall system without risking anything. Similar to position tracking, we let the assets keep track of total opened OI during the asset hook, and let the manager take care of charging the actual fee.