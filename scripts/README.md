# Forge scripts

Useful scripts to interact with the contracts easily

## Best practices
Please refer to [Best Practices for forge scripts](https://book.getfoundry.sh/tutorials/best-practices?highlight=script#scripts) in Foundry tutorial.

## Deploying Mocks to local testnet

To start a local testnet, and copy an private key with initial funds.
```
anvil --port 8000
```


Deploy mocked contract, and write configs to `scripts/inputs/{local_network_id}/config.json`
```
forge script scripts/deploy-mocks.sol --private-key <key_you_copied> --fork-url http://localhost:8000 --broadcast
```
You should see a config file popup in the path above.

Example output
```
== Logs ==
  Start deploying mocked USDC & aggregator! deployer:  0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  usdc 0x5FbDB2315678afecb367f032d93F642f64180aa3
  aggregator 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
  local mocked addresses stored at  /Users/antonasso/programming/lyra/v2-core/scripts/input/31337/config.json

## Setting up (1) EVMs.

==========================

Chain 31337

Estimated gas price: 5 gwei

Estimated total gas used for script: 1857121

Estimated amount required: 0.009285605 ETH

==========================

###
Finding wallets for all the necessary addresses...
##
Sending transactions [0 - 1].
⠉ [00:00:00] [#########################################################################################################################################################] 2/2 txes (0.0s)
Transactions saved to: /Users/antonasso/programming/lyra/v2-core/broadcast/deploy-mocks.sol/31337/run-latest.json

##
Waiting for receipts.
⠙ [00:00:00] [#####################################################################################################################################################] 2/2 receipts (0.0s)
##### anvil-hardhat
✅ Hash: 0x94adb36f094f0b2a9b57581afc0238b96a73a7063a93d4e7bb4402918c7f3502
Contract Address: 0x5fbdb2315678afecb367f032d93f642f64180aa3
Block: 1
Paid: 0.004072292 ETH (1018073 gas * 4 gwei)


##### anvil-hardhat
✅ Hash: 0xc54c5b5eb200c61db51998f8a399c5a188564f05fe48d2756ab28fa6666ef928
Contract Address: 0xe7f1725e7734ce288f8367e1bb143e90bb3f0512
Block: 2
Paid: 0.001594104138553503 ETH (410483 gas * 3.883483941 gwei)
```


## Stimulate contract deployments

Add configs in `scripts/input/{networkId}/config.json` (or run previous step if you're building in local) 

```
forge script scripts/01_deploy_v2.sol --private-key <key> --fork-url <rpc-endpoint> 
```

### Example of mainnet deployment

```
forge script scripts/01_deploy_v2.sol --private-key <key> --fork-url https://mainnet.infura.io/v3/<api-key> --broadcast
```
