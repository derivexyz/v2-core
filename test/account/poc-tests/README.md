# Accounts.sol POC tests

## Folder layout

- All POC tests inherit `AccountPOCHelper` to setup the environment
- Asset contracts used: `OptionToken`, `QuoteWrapper`, `BaseWrapper`

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

### `PortolioRiskPOCManager.t.sol`

using POC manager `PortfolioRiskPOCManager` to test that the manager can do the following

- [ ]  manager can update balance during
  - []  Liquidations
  - []  Settlement
- [ ]  block unsupported manager upgrades

### `SocializedLosses.sol` 

using the same POC manager `PortfolioRiskPOCManager.sol` to test that we can implement socialize loss at the option token level.

- [x]  socialized losses
  - [x]  Option asset ratio post socialized loss
  - [x]  Asset augment finalBalance during transfer (positive → negative?)
  - [x]  Asset ratio stays the same with trade post socialized loss