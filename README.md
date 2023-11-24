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
    <h5 align="center"> The framework to trade all derivatives </h6>
</p> 
</div>


## Installation and Build

```shell
git submodule update --init --recursive
forge build
```

## Running different tests

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

## Documentation

Go to [docs](./docs) to understand the high-level design, transaction flow, and how different **Lyra V2 components** work together.

## Static Analysis - Slither

### Installation

```shell
pip3 install slither-analyzer
pip3 install solc-select
solc-select install 0.8.18
solc-select use 0.8.18
```

### Run Analysis

```shell
slither src
```

#### Triage Issues

```shell
slither src --triage-mode
```

## Deployment

Got to [scripts](./scripts) to understand how to deploy **Lyra v2** to different networks.

## Gas Metrics

See documentation in [test/integration-tests/metrics](./test/integration-tests/metrics/) for more detail.