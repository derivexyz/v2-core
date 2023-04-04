import {
  deployExternalContract,
  deployLyraContract, deployLyraContractWithLibraries,
  executeExternalFunction,
  getExternalContract,
  getLyraContract
} from "../utils/transactions";
import {DeploymentContext} from "../utils/env/deploymentContext";
import {toBN, ZERO_ADDRESS} from "../utils";

export async function deploySystem(dc: DeploymentContext) {
  await deployExternalContract(dc, 'USDC', 'MockERC20', ['USDC', 'USDC']);
  await executeExternalFunction(dc, 'USDC', 'setDecimals', [6])
  await executeExternalFunction(dc, 'USDC', 'mint', [dc.deployerAddress, toBN('100000', 6)])

  await deployExternalContract(dc, 'ETH_SpotFeed', 'MockFeed', []);
  await executeExternalFunction(dc, 'ETH_SpotFeed', 'setSpot', [toBN('2000')])

  await deployLyraContract(dc, 'Accounts', 'Accounts', ['Lyra Protocol Accounts', 'LPA']);

  await deployLyraContract(dc, 'InterestRateModel', 'InterestRateModel', [
    toBN('0.06', 18),
    toBN('0.2', 18),
    toBN('0.4', 18),
    toBN('0.6', 18),
  ]);

  await deployLyraContract(dc, 'CashAsset', 'CashAsset', [
    getLyraContract(dc, 'Accounts').address,
    getExternalContract(dc, 'USDC').address,
    getLyraContract(dc, 'InterestRateModel').address,
    0,
  ]);

  await deployLyraContract(dc, 'OptionAsset', 'MockOption', [
    getLyraContract(dc, 'Accounts').address,
  ]);

  await deployLyraContract(dc, 'Black76', 'Black76', []);
  await deployLyraContractWithLibraries(
    dc, 'MTMCache', 'MTMCache', {
      Black76: getLyraContract(dc, 'Black76').address
    }, []);

  await deployLyraContract(dc, 'ETH_PMRM', 'PMRM', [
    getLyraContract(dc, 'Accounts').address,
    getExternalContract(dc, 'ETH_SpotFeed').address,
    getExternalContract(dc, 'ETH_SpotFeed').address,
    getLyraContract(dc, 'CashAsset').address,
    getLyraContract(dc, 'OptionAsset').address,
    getExternalContract(dc, 'ETH_SpotFeed').address,
    ZERO_ADDRESS,
    getLyraContract(dc, 'MTMCache').address,
  ]);
}
