# Lyra v2-core

Lyra V2 core contracts

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
