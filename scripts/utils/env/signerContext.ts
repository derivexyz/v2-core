import hre from "hardhat";
import {getAllDeploymentEnvs} from "./loadEnv";
import {ethers, Signer, Wallet} from "ethers";
import {JsonRpcProvider, JsonRpcSigner} from "@ethersproject/providers";

export type SignerContext = {
  network: string;
  signer: Signer;
  provider: JsonRpcProvider;
  signerAddress: string;
};

export async function getSignerContext(signerId: number = 0): Promise<SignerContext> {
  const network = hre.network.name;
  const envs = getAllDeploymentEnvs();
  const provider = new ethers.providers.JsonRpcProvider(envs[network].RPC_URL);

  const PK = envs[network][`PRIVATE_KEY${signerId == 0 ? '': `_${signerId}`}`];
  let signer: Signer;
  if (PK == undefined) {
    signer = provider.getSigner(signerId);
  } else {
    signer = new ethers.Wallet(PK, provider);
  }
  return {
    signer,
    network,
    provider,
    signerAddress: await signer.getAddress()
  }
}