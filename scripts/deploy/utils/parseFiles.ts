import chalk from 'chalk';
import { Contract } from 'ethers';
import fs, {readdirSync} from 'fs';
import path from 'path';
import {DeploymentContext} from "../../env/deploymentContext";

export type ContractData =  {
  contractName: string;
  address: string;
  txn: string;
  blockNumber: number;
  source: string;
  abi: any;
  metadata?: any;
}

export function getContractData(c: Contract, name: string, source: string, abi: any, metadata?: any): ContractData {
  return {
    contractName: name,
    source: source,
    address: c.address,
    txn: c.deployTransaction?.hash || '',
    blockNumber: c.deployTransaction?.blockNumber || 0,
    abi,
    metadata
  };
}

export function getContractArtifact(contractName: string) {
  let artifactPath = path.join(__dirname, '../../../artifacts');
  const found = getContractArtifactRecursive(contractName, artifactPath);

  if (found.length == 0) {
    throw new Error(`Contract ${contractName} not found`);
  }

  if (found.length > 1) {
    console.log(found);
    throw new Error(`Multiple instances of ${contractName} found`);
  }

  return require(found[0]);
}

export function getContractArtifactRecursive(contractName: string, artifactPath: string) {

  let found = [];

  for (const i of readdirSync(artifactPath, { withFileTypes: true })) {
    if (i.isDirectory()) {
      found = [...found, ...getContractArtifactRecursive(contractName, path.join(artifactPath, i.name))];
    } else {
      if (i.name == `${contractName}.json`) {
        found.push(path.join(artifactPath, `${contractName}.json`));
      }
    }
  }

  return found;
}





export function addExternalContract(
  dc: DeploymentContext,
  name: string,
  source: string,
  contract: Contract,
) {
  const artifact = getContractArtifact(source);
  let data: ContractData = getContractData(contract, name, source, artifact.abi, { ...artifact, abi: undefined });
  saveFile(dc.network, data, true);
}

export function addContract(
  dc: DeploymentContext,
  name: string,
  source: string,
  contract: Contract,
) {
  const artifact = getContractArtifact(source);
  let data: ContractData = getContractData(contract, name, source, artifact.abi, { ...artifact, abi: undefined });
  saveFile(dc.network, data);
}

function saveFile(network: string, data: ContractData, isExternal?: boolean) {
  const rootPath = path.join(__dirname, "../../..", "deployments",  network);

  let filePath = path.join(rootPath, 'contracts');

  if (!fs.existsSync(filePath)) {
    fs.mkdirSync(filePath);
  }

  if (isExternal) {
    filePath = path.join(rootPath, 'contracts', 'external');
    if (!fs.existsSync(filePath)) {
      fs.mkdirSync(filePath);
    }
  }

  filePath = path.join(filePath, `${data.contractName}.json`);

  fs.writeFileSync(filePath, JSON.stringify(data, null, 2));

  console.log(chalk.grey(`Saved contract ${data.contractName} to ${filePath}`));
}

export function loadLyraContractData(
  dc: DeploymentContext,
  name: string,
) {
  const filePath = path.join(__dirname, "../../../deployments",  dc.network, 'contracts', `${name}.json`);
  return require(filePath);
}

export function loadExternalContractData(
  dc: DeploymentContext,
  name: string,
) {
  const filePath = path.join(__dirname, "../../../deployments",  dc.network, 'contracts/external', `${name}.json`);
  return require(filePath);
}
