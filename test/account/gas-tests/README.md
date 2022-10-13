# Accounts gas benchmarks

## Rough Estimation with forge test (this will underestimate gas)

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
  - [x] Single account USDC <-> 1 account with option: 248,176 gas
  - [x] Single account USDC <-> 100 different accounts with different option: 25,613,723 gas
  - [x] Single account USDC <-> 500 different accounts with different option: 18,4024,761
- [x] Split
  - [x] 600x position account to split 10x short positions to another account: 13,595,450
  - [x] 600x position account to split 100x short positions to another account: 28,608,887 gas  
- [x] Settlement
  - [x] 600x position account to transfer 100x positions out to 0: 2,700,829 gas.
  - [x] 500x position account to transfer 500x positions out to 0: 13,342,178 gas.

