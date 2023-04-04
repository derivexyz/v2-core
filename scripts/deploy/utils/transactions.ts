import chalk from 'chalk';
import { Contract, ContractTransaction, PopulatedTransaction, Signer } from 'ethers';
import { ethers } from 'hardhat';
import {
  addContract,
  addExternalContract,
  loadExternalContractData,
  loadLyraContractData,
} from './parseFiles';
import { etherscanVerification } from './verification';
import {DeploymentContext} from "../../env/deploymentContext";


export function getLyraContract(dc: DeploymentContext, contractName: string): Contract {
  const data = loadLyraContractData(dc, contractName);

  return new Contract(data.target.address, data.source.abi, dc.deployer);
}

export function getExternalContract(
  dc: DeploymentContext,
  contractName: string,
  contractAbiOverride?: string
): Contract {
  const data = loadExternalContractData(dc, contractName);
  let abi = data.source.abi;
  if (contractAbiOverride) {
    const overrideData = loadExternalContractData(dc, contractAbiOverride);
    abi = overrideData.source.abi;
  }
  return new Contract(data.target.address, abi, dc.deployer);
}

export async function deployLyraContract(
  dc: DeploymentContext,
  name: string,
  source: string,
  args: any[]
): Promise<Contract> {
  const contract = await deployContract(name, dc.deployer, undefined, ...args);
  addContract(dc, name, source, contract);
  return contract;
}

export async function deployLyraContractWithLibraries(
  dc: DeploymentContext,
  name: string,
  source: string,
  libs: any,
  args: any[]
): Promise<Contract> {
  const contract = await deployContract(name, dc.deployer, libs, ...args);
  addContract(dc, name, source, contract);
  return contract;
}

export async function deployExternalContract(
  dc: DeploymentContext,
  name: string,
  contractName: string,
  args: any[]
): Promise<Contract> {
  const contract = await deployContract(contractName, dc.deployer, undefined, ...args);
  addExternalContract(dc, name, contractName, contract);
  return contract;
}

export async function deployExternalContractWithLibraries(
  dc: DeploymentContext,
  name: string,
  contractName: string,
  libs: any,
  args: any[]
): Promise<Contract> {
  const contract = await deployContract(contractName, dc.deployer, libs, ...args);
  addExternalContract(dc, name, contractName, contract);
  return contract;
}

export async function deployContract(
  contractName: string,
  deployer: Signer,
  libs?: any,
  ...args: any
): Promise<Contract> {
  console.log('='.repeat(24));
  console.log(`= Deploying ${contractName}`);
  console.log(`= With args: ${args}`);
  let contract: Contract;
  let count = 0;
  console.log('args', args);
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      contract = await (
        await ethers.getContractFactory(contractName, {
          libraries: libs,
        })
      )
        .connect(deployer)
        .deploy(...args, {
          // TODO: remove hardcoded variables
          gasLimit: 15000000,
          gasPrice: 1000000000,
        });

      console.log('= Address:', chalk.green(contract.address));
      console.log('= Tx hash:', chalk.blueBright(contract.deployTransaction.hash));
      console.log('= Nonce:', contract.deployTransaction.nonce);

      while ((await ethers.provider.getTransactionReceipt(contract.deployTransaction.hash)) == null) {
        await sleep(100);
      }
      const receipt = await contract.deployTransaction.wait();
      contract.deployTransaction.blockNumber = contract.deployTransaction.blockNumber || receipt.blockNumber;
      break;
    } catch (e) {
      console.log(e);
      if (e instanceof Error) {
        console.log(e.message.slice(0, 27));
        if (e.message.slice(0, 27) == 'nonce has already been used') {
          continue;
        }
        count--;
        if (count > 0) {
          continue;
        }
        throw e;
      }
    }
  }

  console.log('= Size:', contract.deployTransaction.data.length);
  console.log('='.repeat(24));

  if (!(global as any).pending) {
    (global as any).pending = [];
  }
  (global as any).pending.push(etherscanVerification(contract.address, [...args]));
  return contract;
}

export async function populateLyraFunction(
  dc: DeploymentContext,
  contractName: string,
  fn: string,
  args: any[],
  signer?: Signer,
): Promise<PopulatedTransaction> {
  let contract = getLyraContract(dc, contractName);
  if (signer) {
    contract = contract.connect(signer);
  }
  return contract.populateTransaction[fn](args);
}

export async function executeLyraFunction(
  dc: DeploymentContext,
  contractName: string,
  fn: string,
  args: any[],
  signer?: Signer,
  overrides?: any,
): Promise<ContractTransaction> {
  const contract = getLyraContract(dc, contractName);
  return await execute(signer ? contract.connect(signer) : contract, fn, args, overrides);
}

export async function executeExternalFunction(
  dc: DeploymentContext,
  contractName: string,
  fn: string,
  args: any[],
  signer?: Signer,
): Promise<ContractTransaction> {
  const contract = getExternalContract(dc, contractName);
  return await execute(signer ? contract.connect(signer) : contract, fn, args);
}

export async function callLyraFunction(
  dc: DeploymentContext,
  contractName: string,
  fn: string,
  args: any[],
): Promise<any> {
  const contract = getLyraContract(dc, contractName);
  console.log(chalk.grey(`Calling ${fn} on ${contract.address} with args ${args}`));
  return await contract[fn](...args);
}

export async function callExternalFunction(
  dc: DeploymentContext,
  contractName: string,
  fn: string,
  args: any[],
): Promise<any> {
  const contract = getExternalContract(dc, contractName);
  console.log(chalk.grey(`Calling ${fn} on ${contract.address} with args ${args}`));
  return await contract[fn](...args);
}

export async function execute(c: Contract, fn: string, args: any[], overrides: any = {}): Promise<ContractTransaction> {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      console.log(chalk.grey(`Executing ${fn} on ${c.address} with args ${JSON.stringify(args)}`));
      // TODO: remove hardcoded gasLimit
      overrides = { gasLimit: 15000000, ...overrides };
      const tx = await c[fn](...args, overrides);
      while ((await ethers.provider.getTransactionReceipt(tx.hash)) == null) {
        await sleep(100);
      }
      const receipt = await tx.wait();
      console.log(`Gas used for tx ${chalk.blueBright(receipt.transactionHash)}:`, receipt.gasUsed.toNumber());
      return tx;
    } catch (e) {
      if (e instanceof Error) {
        console.log(e.message.slice(0, 27));
        if (e.message.slice(0, 27) == 'nonce has already been used') {
          continue;
        }
        throw e;
      }
    }
  }
}

export function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}
