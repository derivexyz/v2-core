# Accounts gas benchmarks

## Rough Estimation with forge test (this will underestimate gas)

```shell
forge test --gas-report --match-contract="GAS_"
```

## More accurate estimation

```shell
forge script AccountGasScript
```

- [x] Transfer balance
  - [x] Single USDC transfer: 21,436 gas
  - [x] execute 10 independent transfers: 269,603 gas
  - [x] execute 20 independent transfers: 623,110 gas
  - [x] execute 100 independent transfers: 7,217,277 gas
- [x] Exchange balances between 2 accounts.
  - [x] trade 10 assets: 1,070,324 gas
  - [x] trade 20 assets: 1,230,436 gas
  - [x] trade 100 assets: 8,869,621 gas
- [x] Split: split x positions into x different accounts (update x balances on account 1, and update x other accounts)
  - [x] split 10 positions: 617,994 gas
  - [x] split 20 positions: 890,035 gas
  - [x] split 50 positions: 2,643,314 gas
- [x] Clear Balance
  - [x] clear 10 balances from an account: 132,788 gas
  - [x] clear 20 balances from an account: 264,178 gas
  - [x] clear 50 balances from an account: 636,810 gas
