# Forge scripts

Useful scripts to interact with the contracts easily

## Best practices
Please refer to [Best Practices for forge scripts](https://book.getfoundry.sh/tutorials/best-practices?highlight=script#scripts) in Foundry tutorial.

## Stimulate contract deployments

Add configs in `scripts/input/{networkId}/config.json`

```
forge script scripts/01_Deploy.sol --private-key <key> --fork-url <rpc-endpoint> 
```

Example of mainnet deployment
```
forge script scripts/01_Deploy.sol --private-key <key> --fork-url https://mainnet.infura.io/v3/<api-key> --broadcast
```
