import {SignerContext} from "../utils/env/signerContext";
import {executeExternalFunction, executeLyraFunction, getLyraContract} from "../utils/contracts/transactions";
import {findEvent, toBN} from "../utils";
import {BigNumber} from "ethers";


export async function tradeOption(sc: SignerContext, sellerAcc: number, buyerAcc: number) {
  const tx = await executeLyraFunction(sc, 'Accounts', 'submitTransfers', [
    {
      fromAcc: accB,
      toAcc: accA,
      asset: assetB,
      subId: subIdB,
      amount: amountB,
      assetData: bytes32(0)
    },
    {
      fromAcc: accB,
      toAcc: accA,
      asset: assetB,
      subId: subIdB,
      amount: amountB,
      assetData: bytes32(0)
    }
  ]);
}