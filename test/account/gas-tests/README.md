# Accounts gas benchmarks

## Rough Estimation with forge test (this will underestaimte gas)

```shell
forge test --gas-report --match-contract="GAS_"
```

## More accurate estimation

```shell
forge script AccountGasScript
```

- [x] Transfer
  - [x] Single asset transfer: 37,974 gas
  - [x] Single asset from one account to 100 accounts: 3,978,321 gas
  - [x] Single asset from one account to 500 accounts: 45,413,424 gas
- [x] Trades
  - [x] Singel account USDC <-> 1 account with option: 248,176 gas
  - [x] Single account USDC <-> 100 different accounts wit different option: 25,613,723 gas
  - [x] Single account USDC <-> 500 different accounts with different option: 18,4024,761
- [ ] Settlement
  - [ ] 100x position account to transfer 50x positions out to 0 (Expiration).
  - [ ] 100x position account to transfer 50x positions out to non-zero (split).
  - [ ] 100x position account to transfer 5x positions out to non-zero (split).

