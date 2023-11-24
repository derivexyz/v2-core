# Lyra V2 Testing Guideline

## Running Different Tests

### Only Running Unit Tests

```shell
forge test --match-contract="UNIT_" -vvv
```

### Running Integration Tests

```shell
forge test --match-contract="INTEGRATION_" -vvv
```

### Run Coverage and Generate HTML Report

```shell
# Generate lcov.info
forge coverage --report lcov

# Create a html report
brew install lcov
genhtml lcov.info -out coverage/ --rc lcov_branch_coverage=1 --keep-going --include "src/"
```

## Folder structure

You can find each big **modules** that compose Lyra-V2 in separate folders: list of modules:

- `account`
- `assets`
- `auction`
- `feeds`
- `risk-managers`
- `security-modules`

The `shared` folder contains common contracts that are used across testing for different modules. Currently includes:

- `mocks` folder: shared mocks that should be used in unit test: `MockERC20`, `MockManager`, `MockAsset`.. etc
- `utils`: shared helper functions like encode, decode, building structs... etc

## Testing Guideline

### Unit Tests

we mock everything and aim to ensure **every line of logic** works as expected. Each module has their own unit test in `unit-tests` folder in each module. All unit test contracts should be prefixed with `UNIT_`.

- Use **unit tests** to 
  - describe how each function should work and give the reviewer confidence in the correctness of your code.
  - hit target coverage percentage before requesting review or merging code into bigger branch

There should also be a `mocks` folder which contain own mocks written for this module

  
### Integration Tests

Any tests involving more than 1 real contracts should be put into `integration-tests` folder. All integration tests should be prefixed with `INTEGRATION_`.

If you want to write integration test with a complete test environment setup, you should inherit `IntegrationTestBase`, which already have a standard manager (`srm`), 2 markets  (weth and wbtc), a portfolio margin manager set for **each** market, and all the feeds setup. A simple example can be found with [Misc standard manager test](integration-tests/standard-manager/misc.sol).


### Gas Metrics

The script run a few tests cases and log the gas cost. To run the script:

```shell
forge test --match-contract=GAS_ -vvv
```
