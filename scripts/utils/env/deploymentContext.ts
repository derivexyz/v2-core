import hre from "hardhat";
import {getAllDeploymentEnvs} from "./loadEnv";
import {ethers, Signer, Wallet} from "ethers";
import {JsonRpcProvider, JsonRpcSigner} from "@ethersproject/providers";

export type DeploymentContext = {
  network: string;
  deployer: Signer;
  provider: JsonRpcProvider;
  deployerAddress: string;
};

export async function getDeploymentContext(): Promise<DeploymentContext> {
  const network = hre.network.name;
  const envs = getAllDeploymentEnvs();
  const provider = new ethers.providers.JsonRpcProvider(envs[network].RPC_URL);
  const PK = envs[network].PRIVATE_KEY;
  let deployer: Signer;
  if (PK == undefined) {
    deployer = provider.getSigner(0);
  } else {
    deployer = new ethers.Wallet(PK, provider);
  }
  return {
    deployer,
    network,
    provider,
    deployerAddress: await deployer.getAddress()
  }
}