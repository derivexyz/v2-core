# Portfolio Margining Risk Manager (PMRM)

PMRM is the most powerful part of v2, it unlocks insane amount of capital efficiency, with the cost of high computational resource on EVM.

PMRM only work with 1 asset type (ETH or BTC or DOGE), which means we have separate PMRM contract deployed for each market.

The basic idea of portfolio margining is easy: we run through different market scenarios (spot going up or down, volatility going up or down), and find the worst scenario for the portfolio. This manager need to ensure that even in the most unfavored scenario, the account remains solvent.

In PMRM, all assets' value are evaluated together to determine the final margin, meaning that if you have some base asset (WETH), and some perps, you might be able to short a call with very little extra margin because if price goes up, the loss of short call position might be covered by the base or long perp position.