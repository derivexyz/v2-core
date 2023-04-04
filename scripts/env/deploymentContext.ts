import hre from "hardhat";
import {getAllDeploymentEnvs} from "./loadEnv";
import {ethers, Signer, Wallet} from "ethers";
import {JsonRpcProvider} from "@ethersproject/providers";

export type DeploymentContext = {
  network: string;
  deployer: Signer;
  provider: JsonRpcProvider;
};

export function getDeploymentContext(): DeploymentContext {
  const network = hre.network.name;
  const envs = getAllDeploymentEnvs();
  const provider = new ethers.providers.JsonRpcProvider(envs[network].RPC_URL);
  const PK = envs[network].PRIVATE_KEY;
  const deployer: Signer = PK != undefined ? new ethers.Wallet(PK, provider) : provider.getSigner(0);
  return {
    deployer,
    network,
    provider
  }
}