import {deployLyraContract} from "./utils/transactions";
import {DeploymentContext} from "../env/deploymentContext";

export async function deploySystem(dc: DeploymentContext) {
  const accounts = await deployLyraContract(dc, 'Accounts', 'Accounts', ['Lyra Protocol Accounts', 'LPA']);

  console.log(
    `Accounts deployed to ${accounts.address}`
  );
}
