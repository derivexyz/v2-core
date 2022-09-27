# Lyra V2 Testing Guideline

## Folder structure

You can find each big **modules** that compose Lyra-V2 in separate folders: This should follow the same structure as in `src/`

There are 3 shared folder includes:

- `gas/`: scripts to stimulate gas cost for modules
- `util/`: shared script that can be used by all modules (some shared setup scripts)
- `mocks/`: simple mock contracts that mock returns for unit tests, or more complicated pseudo-contract for POC tests

## Types of Tests

In each module folder, we have at least 2 folders: `unit-tests` and `poc-tests`

- `unit-tests`: where we mock everything and aim to ensure **every line of logic** works as expected. All test contracts should be prefixed with `UNIT_`
- `poc-tests`: where we explore things a bit to see if a certain design makes sense, the goal is to rapidly test ideas and architecture. All test contracts should be prefixed with `POC_`

## Guidelines:

- Use **unit tests** to 
  - describe how each function should work and give the reviewer confidence in the correctness of your code.
  - hit target coverage percentage before requesting review or merging code into bigger branch

- Use **POC tests** to:
  - show how integration would potentially work
  - give ideas around gas cost
  - show how certain design should be improved

- A reviewer should ask the code owner to write more **unit tests** when
  - it's unclear how a certain piece of code works
  - you don't feel comfortable starting building on top of this module.

- A reviewer should ask the code owner to write certain **POC tests** when
  - you don't think the current interface is gonna work with another module
  - you think there are some potential vulnerability while considering other pieces, like reentrancy ... etc

### P.S. Integration tests

We will start writing formal integration tests when more moving pieces are implemented. Those tests will be in a separate folder for all integration tests.