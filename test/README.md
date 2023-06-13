# Lyra V2 Testing Guideline

## Folder structure

You can find each big **modules** that compose Lyra-V2 in separate folders: list of modules:

- `account`

The `shared` folder contains common contracts that are used across testing for different modules. Currently includes:

- `mocks` folder: shared mocks that should be used in unit test: `MockERC20`, `MockManager` and `MockAsset`
- `utils`: shared helper functions like encode, decode, building structs... etc

## Types of Tests

In each module folder, we have at least 3 folders: `unit-tests`, `poc-tests` and `gas-tests` which contain the actual test files:

- `unit-tests`: where we mock everything and aim to ensure **every line of logic** works as expected. All test contracts should be prefixed with `UNIT_`
- `integration-tests`: testing more than 2 contract working together, should be prefixed with `INTEGRATION_`
  - **forge tests**: Tests that will be run and compared in `.gas-snapshot`. All test contracts should be prefixed with `GAS_`. These tests are expected to "underestimate" the gas cost when it comes to storage-related operations. Better be used to estimate gas costs around calculations.
  - **forge script estimation**: Follow the template in [account/gas-test/GasScript](./account/gas-tests/GasScript.t.sol) to use script feature to estimate real world gas costs. These will be less flexible compared to forge tests, but gives more accurate results.

There should also be a `mocks` folder which contain own mocks written for this module, mainly for POC tests.

## Guidelines:

- Use **unit tests** to 
  - describe how each function should work and give the reviewer confidence in the correctness of your code.
  - hit target coverage percentage before requesting review or merging code into bigger branch

- Use **POC tests** to:
  - show how integration would potentially work
  - give ideas around gas cost
  - show how certain design should be improved

- documentation
  - unit tests: aim to achieve full coverage, no additional documentation needed
  - poc tests: must have a `README.md` in the `poc-tests` folder that outline all the tests as checklist.
  - gas test: must have a `README.md` in the `gas-tests` folder which outline all the benchmark scenarios and fill in the gas cost at the end.

- A reviewer should ask the code owner to write more **unit tests** when
  - it's unclear how a certain piece of code works
  - you don't feel comfortable starting building on top of this module.

- A reviewer should ask the code owner to write certain **POC tests** when
  - you don't think the current interface is gonna work with another module
  - you think there are some potential vulnerability while considering other pieces, like reentrancy ... etc

### P.S. Integration tests

We will start writing formal integration tests when more moving pieces are implemented. Those tests will be in a separate folder for all integration tests.