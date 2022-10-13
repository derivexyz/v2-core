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
  - [x] Single USDC transfer: 28,666 gas
  - [x] execute 10 independent transfers: 341,903 gas
  - [x] execute 20 independent transfers: 767,710 gas
  - [x] execute 100 independent transfers: 7940,277 gas
- [x] Exchange balances between 2 accounts.
  - [x] single trade: 143,902 gas
  - [x] trade 10 assets: 1118,492 gas
  - [x] trade 20 assets: 1316,022 gas
  - [x] trade 100 assets: 9261,437 gas
- [x] Split: split x positions into x different accounts (update x balances on account 1, and update x other accounts)
  - [x] split 10 positions: 1059,049 gas
  - [x] split 20 positions: 1385,800 gas
  - [x] split 50 positions: 3303,209 gas
- [x] Clear Balance
  - [x] clear 10 balances from an account: 132,807 gas
  - [x] clear 20 balances from an account: 264,197 gas
  - [x] clear 50 balances from an account: 636,829 gas
