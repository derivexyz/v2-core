import {SignerContext} from "../utils/env/signerContext";
import {executeExternalFunction, executeLyraFunction, getLyraContract} from "../utils/contracts/transactions";
import {findEvent, toBN} from "../utils";
import {BigNumber} from "ethers";

export async function seedPMRMAccount(sc: SignerContext, balance: string = "100000", ownerOverride?: string) {
  await executeExternalFunction(sc, 'USDC', 'mint', [sc.signerAddress, toBN(balance, 6)])
  await executeExternalFunction(sc, 'USDC', 'approve', [getLyraContract(sc, 'CashAsset').address, toBN(balance, 6)])
  const tx = await executeLyraFunction(sc, 'Accounts', 'createAccount', [ownerOverride || sc.signerAddress, getLyraContract(sc, 'ETH_PMRM').address]);
  const accountId = (await findEvent(tx, 'AccountCreated')).accountId as BigNumber;
  await executeLyraFunction(sc, 'CashAsset', 'deposit', [accountId, toBN(balance, 6)]);
  return accountId;
}