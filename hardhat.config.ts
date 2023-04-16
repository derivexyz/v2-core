import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";
import "@nomiclabs/hardhat-etherscan";
import { getHardhatNetworkConfigs} from "./scripts/utils/env/loadEnv";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.17",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    ...getHardhatNetworkConfigs(),
  },
  etherscan: {
    apiKey: {
      "conduit-testnet": 'APIKeyNotNeeded'
    },
    customChains: [
      {
        network: "conduit-testnet",
        chainId: 901,
        urls: {
          apiURL: "https://explorerl2-lyra-devnet.t.conduit.xyz/api",
          browserURL: "https://explorerl2-lyra-devnet.t.conduit.xyz/"
        }
      }
    ]
  }
};

export default config;
