import chalk from 'chalk';
import {BigNumber, Contract, ContractTransaction, PopulatedTransaction, Signer} from 'ethers';
import { ethers } from 'hardhat';
import {
  addContract,
  addExternalContract,
  loadExternalContractData,
  loadLyraContractData,
} from './parseFiles';
import {SignerContext} from "../env/signerContext";
import {etherscanVerification} from "./verification";


export function getLyraContract(sc: SignerContext, contractName: string): Contract {
  const data = loadLyraContractData(sc, contractName);
  return new Contract(data.address, data.abi, sc.signer);
}

export function getExternalContract(
  sc: SignerContext,
  contractName: string,
  contractAbiOverride?: string
): Contract {
  const data = loadExternalContractData(sc, contractName);
  let abi = data.abi;
  if (contractAbiOverride) {
    const overrideData = loadExternalContractData(sc, contractAbiOverride);
    abi = overrideData.abi;
  }
  return new Contract(data.address, abi, sc.signer);
}

export async function deployLyraContract(
  sc: SignerContext,
  name: string,
  source: string,
  args: any[],
  overrides: any = {},
  libs: any = {},
): Promise<Contract> {
  const contract = await deployContract(source, sc.signer, args, overrides, libs);
  addContract(sc, name, source, contract);
  return contract;
}

export async function deployExternalContract(
  sc: SignerContext,
  name: string,
  source: string,
  args: any[],
  overrides: any = {},
  libs: any = {},
): Promise<Contract> {
  const contract = await deployContract(source, sc.signer, args, overrides, libs);
  addExternalContract(sc, name, source, contract);
  return contract;
}

export async function deployContract(
  contractName: string,
  deployer: Signer,
  args: any[],
  overrides: any,
  libs?: any,
): Promise<Contract> {
  console.log('='.repeat(24));
  console.log(`= Deploying ${contractName}`);
  console.log(`= With args: ${args}`);
  let contract: Contract;
  let count = 0;
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
          gasLimit: 15_000_000,
          // gasPrice: toBN('2', 9),
          ...overrides
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

  await etherscanVerification(contract.address, [...args]);

  return contract;
}

export async function executeLyraFunction(
  sc: SignerContext,
  contractName: string,
  fn: string,
  args: any[],
  overrides?: any,
): Promise<ContractTransaction> {
  const contract = getLyraContract(sc, contractName);
  return await execute(contract, fn, args, overrides);
}

export async function executeExternalFunction(
  sc: SignerContext,
  contractName: string,
  fn: string,
  args: any[],
  overrides: any = {}
): Promise<ContractTransaction> {
  const contract = getExternalContract(sc, contractName);
  return await execute(contract, fn, args, overrides);
}

export async function callLyraFunction(
  sc: SignerContext,
  contractName: string,
  fn: string,
  args: any[],
): Promise<any> {
  const contract = getLyraContract(sc, contractName);
  console.log(chalk.grey(`Calling ${fn} on ${contract.address} with args ${args}`));
  return await contract[fn](...args);
}

export async function callExternalFunction(
  sc: SignerContext,
  contractName: string,
  fn: string,
  args: any[],
): Promise<any> {
  const contract = getExternalContract(sc, contractName);
  console.log(chalk.grey(`Calling ${fn} on ${contract.address} with args ${args}`));
  return await contract[fn](...args);
}

export async function execute(c: Contract, fn: string, args: any[], overrides: any = {}): Promise<ContractTransaction> {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    try {
      console.log(chalk.grey(`Executing ${fn} on ${c.address} with args ${JSON.stringify(args)} overrides ${JSON.stringify(overrides)}`));
      // TODO: remove hardcoded gasLimit
      overrides = {
        gasLimit: 15_000_000,
        // gasPrice: toBN('2', 9),
        ...overrides
      };
      const tx = await c[fn](...args, overrides);
      while ((await ethers.provider.getTransactionReceipt(tx.hash)) == null) {
        await sleep(100);
      }
      const receipt = await tx.wait();
      console.log(`Gas used for tx ${chalk.blueBright(receipt.transactionHash)}:`, receipt.gasUsed.toNumber());
      return tx;
    } catch (e) {
      if (e instanceof Error) {
        console.log(chalk.red(e.message.slice(0, 100)));
        if (e.message.slice(0, 27) == 'nonce has already been used') {
          continue;
        } else if (e.message.slice(0, 12) == 'bad response') {
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
