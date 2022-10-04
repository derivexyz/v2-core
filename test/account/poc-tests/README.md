## Accounts.sol POC tests scaffold

### `Allowances.sol`

POC tests on setting allowance on a real world asset with `subId`

- [x] Can transfer asset with asset allowance
- [x] Can transfer asset with subId allowance
- [x] Can only auth to trade with specific option token subId

### `Lending.t.sol`

POC asset contract to handle lending & accrue interest on adjustmentHook.

- [x]  Deposits / Withdrawals assets
- [x]  accrue interest when adjusting balance
- [x]  accrue interest with 0 amount triggers
- [ ]  apply socialized losses

### `ProtfolioRiskManager.sol` 

POC manager contract that 

- [ ]  manager can update balance
    - [ ]  Forceful Liquidations
    - [ ]  Settlement
- [ ]  block unsupported manager
- [x]  socialized losses
    - [x]  Option asset ratio post socialized loss
    - [x]  Asset augment finalBalance during transfer (positive → negative?)
    - [x]  Asset ratio stays the same with trade post socialized loss