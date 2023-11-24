# Terminology 

## Cash

We use **cash** to refer to a wrapped version of USDC in our internal accounting system. When users deposit USDC into `CashAsset`, it is then added to someone's balance in `SubAccounts`. You can always burn **cash** and withdraw USDC.

Cash is also used for settlement: 

* For options: when a long option position expires with value, our manager will credit **cash** balance to the corresponding account; when a short option position expires at a loss, we will decrease the cash in your balance too. 
* For perps: whenever a perp position is updated, we realize all unrealized PNL into cash.

There are several scenarios where some accounts' cash balances can be negative, for example, when someone borrows USDC from the system, or because an account loses some money trading options/perps.

When an account is insolvent, we also allow liquidators to bid on the portfolio with **cash**.

## Margin

We use the word **"margin"** to determine the final net worth of a position or an account. **Margin** is usually an `int`, as it can be both positive or negative. 

### Margin for Positions

If the margin of a position is positive, it must be a position that's making the portfolio healthier, for example, cash balance, base assets (ETH, BTC), or long options. On the other hand, a position that is risky or usually requires "collateral", would have negative margin, for example, short options, or any perp positions.

> 📋 The sign of margin if balances of each asset are positive/negative


| Asset | Positive Balance | Negative Balance |
| -------- | -------- | -------- |
| Cash     | +     | -     |
| BaseAsset (ETH, BTC)     | +     | N/A (cannot short base asset)    |
| Option     | + (PMRM); 0 (SRM)     | -     |
| Perp     | -     | -     |


### Accounts Margins

Throughout the codebase, we constantly sum up **margin** across all positions to determine the final **margin** for a subaccount. There are also 2 different "margin formulas": 

* **Initial Margin (IM)**: The health level to determine if a trade can be opened. If an account's final **IM** is lower than zero, the trade should revert. (unless it's a trade improving the IM)

* **Maintenance Margin (MM)**: The health level where liquidation kicks in. If MM < 0, the liquidation module can flag the account as "insolvent" and start a Dutch auction to sell the portfolio at a discount to users.

## Contingency

When calculating **Initial Margin**, both SRM and PMRM have different logic to apply penalties called contingencies. For example, when an oracle reports a price/vol value with a low confidence score, we will apply an "oracle contingency". This results in a **decrease** in the **initial margin**, making it harder to open risky trades (requiring more collateral) to ensure our system remains solvent.
