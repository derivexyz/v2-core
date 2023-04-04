import {readdirSync} from "fs";
import path from "path";
import dotenv from "dotenv";
import {NetworkUserConfig} from "hardhat/src/types/config";

export type NetworkEnv = {
  RPC_URL: string;
  PRIVATE_KEY?: string;
  ETHERSCAN_KEY?: string;
}

export function getAllDeploymentEnvs() {
  const rootPath = path.join(__dirname, '../../deployments');
  const res: {[key:string]: NetworkEnv} = {};
  for (const i of readdirSync(rootPath, { withFileTypes: true })) {
    if (i.isDirectory()) {
      const publicConfig: any = dotenv.config({
        path: path.join(rootPath, i.name, '.env.public')
      });
      const privateConfig: any = dotenv.config({
        path: path.join(rootPath, i.name, '.env.private')
      });
      res[i.name] = {
        ...publicConfig.parsed,
        ...privateConfig.parsed
      } as NetworkEnv;

      if (!res[i.name].RPC_URL) {
        throw Error(`No RPC_URL in network <${i.name}> config`)
      }
    }
  }
  return res;
}

export function getHardhatNetworkConfigs(): {[key:string]: NetworkUserConfig} {
  const res: {[key:string]: { url: string }} = {};
  const envs = getAllDeploymentEnvs();
  for (const [key, value] of Object.entries(envs)) {
    res[key] = {
      url: value.RPC_URL
    }
  }
  return res;
}
