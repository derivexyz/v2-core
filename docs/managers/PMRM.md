# Portfolio Margining Risk Manager (PMRM)

> Make sure to read through [terminology](../terminology.md) first to understand the terms we are using here.

## Intro

PMRM is the most powerful component of v2, unlocking an immense amount of capital efficiency, albeit at the cost of high computational resources on the EVM.

PMRM only works with one asset type (ETH, BTC, or DOGE), meaning we have separate PMRM contracts deployed for each market.

## Risk Check

The basic idea of portfolio margining is straightforward: we simulate different market scenarios (spot going up or down, volatility increasing or decreasing), and identify the worst-case scenario for the portfolio. This manager ensures that, even in the most unfavorable scenario, the account remains solvent.

In PMRM, all assets' values are evaluated together to determine the final margin. This means that if you have some base assets (WETH) and some perps, you might be able to short a call with very little extra margin. This is because if the price increases, the loss from the short call position might be offset by gains in the base or long perp positions.

### Trusted Roles

* **Trusted Risk Assessor**: The owner can appoint an address as a trusted risk assessor. If a transfer is submitted by a trusted risk assessor, then we skip all the scenarios involving volatility shocks.
