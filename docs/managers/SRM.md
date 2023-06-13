# Standard Risk Manager (SRM)

Standard manager is a simple margining system that require you to post margin on each individual position you opened. It is meant to be used by usual traders who don't want to have a giant portfolio. The standard manager will only be deployed once and be shared by all markets, meaning you have hold ETH perp position, BTC options all in the same account.

In SRM, If you long a perp, you will be asked to add some margin (% of spot price), similar to any perp exchanges. If you want to short some options, you will need to add extra cash that is the same if you short it from a new account.

In SRM, longing an option doesn't contribute anything to margin, meaning that if you have bunch of long options in your account and they all have value, you **cannot** use them as "collateral" and open other dangerous position like perp, or withdraw cash.
The only exception is when this long option capped the max loss of another short option position. For example, if you long a 2000 CALL, and short a 1800 CALL with the same expiry, your max loss is capped at $200. So it doesn't matter how the market fluctuate, you will not be liquidated if you have this "call-spread" with $200 cash as collateral.

There is a special variable `borrowingEnabled`, which if set to true, will allow people to have "negative cash" if the overall net margin is > 0 (meaning you can borrow cash out of your base / perp) positions. 

In the manager hook when SRM is evaluation an account, it simply run through all assets in each market (and expiry), and sum up the "net margin". Perps and options will only have **negative margin**, while base and cash asset can have **positive margin**. If the sum of all margin is above 0, the trade can go through.