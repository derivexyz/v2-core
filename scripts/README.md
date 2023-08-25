# Deployment script

## Setup

Add an `.env` file with following:

```python
# required
PRIVATE_KEY=<your key>
```

And run this to make sure it's loaded in shell
```
source .env
```

Also, it's easier to add the rpc network into `foundry.toml`, so we can use the alias later in the script

```
[rpc_endpoints]
sepolia = https://sepolia.infura.io/v3/26251a7744c548a3adbc17880fc70764
```

Currently we have the default RPC ready for:

```
sepolia
conduit_prod
conduit_staging
```


## Deploying to a new network 

## 1. Deploy mock contracts if needed:

If you don't need to deploy mock contracts (for example doing on mainnet or L2), just add the following config to `scripts/input/<networkId>/config.json`:

```json
{
  "usdc": "0xe80F2a02398BBf1ab2C9cc52caD1978159c215BD",
  "useMockedFeed": false,
  "wbtc": "0xF1493F3602Ab0fC576375a20D7E4B4714DB4422d",
  "weth": "0x3a34565D81156cF0B1b9bC5f14FD00333bcf6B93"
}
```

If you're deploying to a new testnet and need to deploy some mocked USDC, WBTC and WETH, we have a setup script already which generates the config file for the network. Let's assume the networkId is 999, run the following command:

```shell
# where the config will live
mkdir scripts/input/999

# deploy mocks and write (or override) config. 
# Note: Replace sepolia with other network alias if needed
forge script scripts/deploy-mocks.s.sol  --rpc-url sepolia --broadcast
```

## 2. Deploy Core contracts

Run the following script, (assuming network id = 999)

```shell
# create folder to store deployed addresses
mkdir deployments/999

forge script scripts/deploy-core.s.sol  --rpc-url sepolia --broadcast
```


To change parameters: goes to `scripts/config.sol` and update the numbers.

Example Output 
```
== Logs ==
  Start deploying core contracts! deployer:  0x77774066be05E9725cf12A583Ed67F860d19c187
  predicted addr 0xfe3e0ACFA9f4165DD733FCF6912c9d90c3aC0008
  Core contracts deployed and setup!
  Written to deployment  v2-core/deployments/901/core.json
```

The configs will now be written as something like this: (example `deployment/901/core.json`)
```
{
  "auction": "0x6772299e3b0C7FF1AC8728F942A252e72CA1b521",
  "cash": "0x41d847D2dF78b27c0Bc730F773993EfE247c3f78",
  "rateModel": "0x1d61223Caea948f97d657aB3189e23F48888b6b0",
  "securityModule": "0x59E8b474a8061BCaEF705c7B93a903dE161FD149",
  "srm": "0xfe3e0ACFA9f4165DD733FCF6912c9d90c3aC0008",
  "srmViewer": "0xDb1791026c3824441FAe8A105b08E40dD02e1469",
  "stableFeed": "0xb77efe3e7c049933853e2C845a1412bCd36a2899",
  "subAccounts": "0x1dC3c8f65529E32626bbbb901cb743d373a7193e"
}
```

### 3. Deploy Single Market

Running this script will create a new set of "Assets" for this market, create a new PMRM, and link everything to the shared standard manager + setup default parameters

Not that you need to pass in the "market" you want to deploy with env variables. Similarly you can update default params in `scripts/config.sol` before running the script.

```shell
MARKET_NAME=weth forge script scripts/deploy-market.s.sol  --rpc-url sepolia --broadcast
```

#### Output
```
== Logs ==
  Start deploying new market:  weth
  Deployer:  0x77774066be05E9725cf12A583Ed67F860d19c187
  target erc20: 0x3a34565D81156cF0B1b9bC5f14FD00333bcf6B93
  All asset whitelist both managers!
  market ID for newly created market: 1
  Written to deployment  /lyra/v2-core/deployments/999/weth.json
```

And every address will be stored in `deployments/999/weth.json`

```json
{
  "base": "0xF79FFb054429fb2b261c0896490f392fc8Ab998d",
  "forwardFeed": "0x48326634Ad484F086A9939cCF162960d8b3ce1D0",
  "iapFeed": "0x31de1F10347f8CBa52242A95dC7934FA98E70975",
  "ibpFeed": "0x45eC148853607f0969c5aB053fd10d59FA340B0A",
  "option": "0xc8FE03d1183053c1F3187c76A8A003323B9C5314",
  "perp": "0xAFf5ae727AecAf8aD4B03518248B5AD073edd99d",
  "perpFeed": "0xBbfb755C9B7A5DDEBc67651bAA15C659d001baD1",
  "pmrm": "0x105E635F61676E3a71bFAE7C02D17acd81A9b1D0",
  "pmrmLib": "0x991f05b9b450333347d266Fe362CFE19973FA70A",
  "pmrmViewer": "0x9F21BFA6607Eb71372B2654dfd528505896cB90B",
  "pricing": "0xD9d8d903707e03A7Cb1D8c9e3338F4E1Cc5Ec136",
  "rateFeed": "0x95721653d1E1C77Ac5cE09c93f7FF11dd5D87190",
  "spotFeed": "0x8a4A11BBE33C25F03a8b11EaC32312E2360858aD",
  "volFeed": "0xc97d681A8e58e4581F7456C2E5bC9F4CF26b236a"
}
```

You can update the market name to "wbtc" and run the script again to deploy wbtc markets.