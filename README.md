# Lyra V2

[![foundry-rs - foundry](https://img.shields.io/static/v1?label=foundry-rs&message=foundry&color=blue&logo=github)](https://github.com/foundry-rs/foundry "Go to GitHub repo")
[![CI](https://github.com/lyra-finance/v2-core/actions/workflows/ci.yml/badge.svg)](https://github.com/lyra-finance/v2-core/actions/workflows/ci.yml)
[![Slither Analysis](https://github.com/lyra-finance/v2-core/actions/workflows/slither.yml/badge.svg)](https://github.com/lyra-finance/v2-core/actions/workflows/slither.yml)
[![codecov](https://codecov.io/gh/lyra-finance/v2-core/branch/master/graph/badge.svg?token=43B951MYIN)](https://codecov.io/gh/lyra-finance/v2-core)

<div align="center">
  <p align='center'>
    <br>
    <br>
    <img src='./docs/imgs/overall/logo.png' alt='lyra' width="300" />
    <h5 align="center"> Cool slogan goes here </h6>
</p> 
</div>


## Installation and Build

```shell
git submodule update --init --recursive
forge build
```

## Running different tests

Only running unit tests

```shell
forge test --match-contract="UNIT_" -vvv
```

Running POC tests

```shell
forge test --match-contract="POC_" -vvv
```

## Documentation

Go to [docs](./docs) to understand the high level of the design, transaction flow and how different **Lyra v2 components** works together.

## Static Analysis - Slither
 
### Installation

```shell
pip3 install slither-analyzer
pip3 install solc-select
solc-select install 0.8.13
solc-select use 0.8.13
```

### Run analysis

```shell
slither src
```

#### Triage issues

Make sure to triage all findings introduced by new PR. They should be appended to `slither.db.json` after the following:

```shell
slither src --triage-mode
```