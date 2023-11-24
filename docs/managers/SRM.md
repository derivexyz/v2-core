# Standard Risk Manager (SRM)

> Make sure to read through [terminology](../terminology.md) first to understand the terms we are using here.

## Basics

The Standard Manager is a simple margining system that requires you to collateralize each individual position you open. It is designed for typical traders who don't have a large portfolio. The Standard Manager is deployed only once and shared across all markets, allowing you to hold ETH perp positions, BTC options, and more, all in the same account.

In SRM, if you take a long position in a perp, you will need some collateral, similar to other perp exchanges. If you want to short more options, you will need to add extra cash, the same as if you shorted them from a new account.

In SRM, taking a long position in an option doesn't contribute to the margin (margin = 0), meaning that if you have a collection of long options in your account and they all have value, you **cannot** use them as "collateral" to open other risky positions like perps, or to withdraw cash.
The only exception is when the long option limits the maximum loss of another short option position. For example, if you long a 2000 CALL and short a 1800 CALL with the same expiry, your maximum loss is capped at $200. Therefore, regardless of market fluctuations, you will not be liquidated if you have this "call spread" with $200 cash as collateral.

## Borrowing

There is a special variable `borrowingEnabled`, which, if set to true, allows users to have "negative cash" as long as the overall net margin is greater than 0 (meaning you can borrow cash from your base/perp positions).

## Risk Check

In the manager hook when SRM is checking an account, it simply runs through all assets in each market (and expiry), summing up the "net margin". Perps and options will only have **negative margin**, while base and cash assets can have **positive margin**. If the sum of all margins is above 0, the trade can go through.

### Option Margin Calculation

* **Isolated Margin**: The Standard Manager has a formula to determine the minimum margin for a single option position, called **isolated margin**. For example, shorting a 2000 ETH call might have an isolated margin of -200, meaning you need $200 worth of collateral (USDC or other assets). Note that isolated margins are always less than or equal to 0.
* **Max Loss**: As mentioned above, if someone holds a long option along with a short option, it's possible that the long option caps the maximum loss of the short position (forming a spread). To capture this, we also go through all the strike prices in a single expiry, to determine the maximum loss if this is the settlement price. The max loss is always less than or equal to 0.

The overall **margin** of an expiry is determined by the better of the isolated margin or max loss. However, note that if a portfolio has 5 total long calls and 6 total short calls, iterating through all the strikes might not find the cases where the portfolio loses the most money (the worst-case scenario being the price going to infinity). In this case (if `expiryHolding.netCalls < 0`), we apply another `unpairedScale` to **maxLossMargin**.

### Trusted Roles

* **Trusted Risk Assessor**: The owner can appoint an address as a trusted risk assessor. If a transfer is submitted by a trusted risk assessor, we allow a trade to go through if the **maintenance margin** is above 0.
