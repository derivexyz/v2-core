# Accounts gas benchmarks

## Rough Estimation with forge test (this will underestaimte gas)

```shell
forge test --gas-report --match-contract="GAS_"
```

## More accurate estimation

```shell
forge script AccountGasScript
```

- [ ]  Gas Testing
    - [ ]  Large
        - [ ]  100x position account to transfer 50x positions out to 0 (Expiration).
        - [ ]  100x position account to transfer 50x positions out to non-zero (split).
        - [ ]  100x position account to transfer 4x positions out to non-zero (split).
        - [ ]  Add 65kth heldAsset to a 65k heldAsset.length account
    - [ ]  Small
        - [ ]  0x position account to get 10x positions
        - [x]  2x subId transfer between two 0x position accounts [275k gas]

