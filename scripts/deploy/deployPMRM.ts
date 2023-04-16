import {
  deployExternalContract,
  deployLyraContract,
  executeExternalFunction,
  executeLyraFunction,
  getExternalContract,
  getLyraContract
} from "../utils/contracts/transactions";
import {SignerContext} from "../utils/env/signerContext";
import {toBN, ZERO_ADDRESS} from "../utils";

export async function deployPMRM(sc: SignerContext) {
  await deployExternalContract(sc, 'USDC', 'MockERC20', ['USDC', 'USDC']);
  await executeExternalFunction(sc, 'USDC', 'setDecimals', [6])

  await deployExternalContract(sc, 'ETH_SpotFeed', 'MockFeed', []);
  await executeExternalFunction(sc, 'ETH_SpotFeed', 'setSpot', [toBN('2000')])

  await deployLyraContract(sc, 'Accounts', 'Accounts', ['Lyra Protocol Accounts', 'LPA']);

  await deployLyraContract(sc, 'InterestRateModel', 'InterestRateModel', [
    toBN('0.06', 18),
    toBN('0.2', 18),
    toBN('0.4', 18),
    toBN('0.6', 18),
  ]);

  await deployLyraContract(sc, 'CashAsset', 'CashAsset', [
    getLyraContract(sc, 'Accounts').address,
    getExternalContract(sc, 'USDC').address,
    getLyraContract(sc, 'InterestRateModel').address,
    0,
  ]);

  await deployLyraContract(sc, 'OptionAsset', 'MockOption', [
    getLyraContract(sc, 'Accounts').address,
  ]);

  await deployLyraContract(sc, 'Black76', 'Black76', []);
  await deployLyraContract(sc, 'MTMCache', 'MTMCache', [], {}, {
    Black76: getLyraContract(sc, 'Black76').address
  });

  await deployLyraContract(sc, 'ETH_PMRM', 'PMRM', [
    getLyraContract(sc, 'Accounts').address,
    getExternalContract(sc, 'ETH_SpotFeed').address,
    getExternalContract(sc, 'ETH_SpotFeed').address,
    getLyraContract(sc, 'CashAsset').address,
    getLyraContract(sc, 'OptionAsset').address,
    getExternalContract(sc, 'ETH_SpotFeed').address,
    ZERO_ADDRESS,
    getLyraContract(sc, 'MTMCache').address,
  ]);

  await executeLyraFunction(sc, 'CashAsset', 'setWhitelistManager', [
    getLyraContract(sc, 'ETH_PMRM').address, true
  ]);
}
