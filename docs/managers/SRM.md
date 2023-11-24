# Standard Risk Manager (SRM)

> Make sure to read through [terminology](../terminology.md) first to understand the terms we are using here.

## Basics

The Standard Manager is a simple margining system that requires you to collateralize each individual position you open. It is designed for usual traders who don't have a giant portfolio. The Standard Manager will only be deployed once and shared by all markets, meaning you can hold ETH perp positions, BTC options, and more, all in the same account.

In SRM, if you long a perp, you will be asked to add some margin (% of spot price), similar to other perp exchanges. If you want to short some options, you will need to add extra cash, the same as if you shorted it from a new account.

In SRM, longing an option doesn't contribute anything to margin, meaning that if you have a bunch of long options in your account and they all have value, you **cannot** use them as "collateral" to open other risky positions like perp, or to withdraw cash.
The only exception is when the long option caps the max loss of another short option position. For example, if you long a 2000 CALL, and short a 1800 CALL with the same expiry, your max loss is capped at $200. So, no matter how the market fluctuates, you will not be liquidated if you have this "call spread" with $200 cash as collateral.

## Borrowing

There is a special variable `borrowingEnabled`, which, if set to true, allows users to have "negative cash" as long as the overall net margin is > 0 (meaning you can borrow cash out of your base/perp positions).

## Risk Check

In the manager hook when SRM is checking an account, it simply runs through all assets in each market (and expiry), summing up the "net margin". Perps and options will only have **negative margin**, while base and cash assets can have **positive margin**. If the sum of all margins is above 0, the trade can go through.

### Option Margin Calculation

* **Isolated Margin**: The Standard Manager has a formula to determine the minimum margin for a single option position, called **isolated margin**. For example, shorting a 2000 ETH call might have an isolated margin of -200, meaning you need $200 worth of collateral (USDC or other assets).

### Trusted Roles

* **Trusted Risk Assessor**: The owner can set an address as a trusted risk assessor. If a transfer is submitted by a trusted risk assessor, we allow a trade to go through if the **maintenance margin** is above 0.
