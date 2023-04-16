import {BaseAgent} from "./baseAgent";
import {SignerContext} from "../../utils/env/signerContext";
import {seedPMRMAccount} from "../../seed/seedPMRMAccount";
import {BigNumber} from "ethers";
import chalk from "chalk";
import {Simulation} from "../simulation";
import {getOptionParams} from "../../utils/options/optionEncoding";
import {callPrice, optionPrices, putPrice, tAnnualised} from "../../utils/options/blackScholes";
import {EMPTY_BYTES, fromBN, toBN} from "../../utils";
import {executeLyraFunction} from "../../utils/contracts/transactions";
import {Trade} from "../market/market";

export type MarketMakerAgentConfig = {
  num: number;
  initialBalance: string;
}


export class MarketMakerAgent extends BaseAgent {
  config: MarketMakerAgentConfig;
  accountId: BigNumber;
  constructor(sc: SignerContext, simulation: Simulation, config: MarketMakerAgentConfig) {
    super(sc, simulation);
    this.config = config;
  }

  async init(adminContext: SignerContext) {
    this.accountId = await seedPMRMAccount(adminContext, this.config.initialBalance, this.sc.signerAddress);
    // hack to avoid needing signatures for now
    let nonce = await this.sc.signer.getTransactionCount();
    for (const agent of this.simulation.agents) {
      if (agent === this) continue;
      this.pendingTxs.push(executeLyraFunction(this.sc, 'Accounts', 'setApprovalForAll', [agent.sc.signerAddress, true], {nonce: nonce++}));
    }
  }

  async step() {
    console.log(chalk.grey(`Market Maker ${this.sc.signerAddress} step`))
    // place a trade on the market
    this.clearAllOrders();
    await this.placeTradesOnMarket();
  }

  clearAllOrders() {
    this.market.clearAllOrders(this.accountId);
  }

  async placeTradesOnMarket() {
    // get random boardId from market
    const allBoards = Object.keys(this.market.boards);
    const trades: Trade[] = [];
    for (const boardId of allBoards) {
      const optionDetails = getOptionParams(BigNumber.from(boardId));
      let bsPrice;
      const args = [
        tAnnualised(this.simulation.currentTime, optionDetails.expiry),
        +fromBN(await this.simulation.getVol(boardId)),
        +fromBN(await this.simulation.getSpotPrice()),
        +fromBN(optionDetails.strike),
        +fromBN(await this.simulation.getRate())
      ];
      if (optionDetails.isCall) {
        bsPrice = callPrice(
          ...args
        );
      } else {
        bsPrice = putPrice(
          ...args
        );
      }

      for (const step of [1, 2, 3, 4]) {
        trades.push(...this.market.placeLimitOrder(
          boardId,
          {
            accountId: this.accountId,
            amount: toBN('5'),
            pricePerOption: toBN((bsPrice).toString()).mul(99 - step).div(100), // 95% of mark price
            collateralPerOption: toBN('0'),
            signature: ""
          },
          true
        ));

        trades.push(...this.market.placeLimitOrder(
          boardId,
          {
            accountId: this.accountId,
            amount: toBN('5'),
            pricePerOption: toBN((bsPrice).toString()).mul(101 + step).div(100), // 105% of mark price
            collateralPerOption: toBN('1000'),
            signature: ""
          },
          false
        ));
      }
    }

    if (trades.length > 0) {
      await executeLyraFunction(this.sc, 'Accounts', 'submitTransfers', [trades, EMPTY_BYTES]);
    }
  }
}