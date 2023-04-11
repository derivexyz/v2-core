import {BaseAgent} from "./baseAgent";
import {BigNumber} from "ethers";
import {SignerContext} from "../../utils/env/signerContext";
import {seedPMRMAccount} from "../../seed/seedPMRMAccount";
import chalk from "chalk";
import {Simulation} from "../simulation";
import {math} from "../../../typechain-types/lib/lyra-utils/src";
import {toBN} from "../../utils";

export type TraderAgentConfig = {
  num: number;
  initialBalance: string;
  numTrades: number;
  tradeSize: [string, string];
}

export class TraderAgent extends BaseAgent {
  config: TraderAgentConfig;
  accountId: BigNumber;
  constructor(sc: SignerContext, simulation: Simulation, config: TraderAgentConfig) {
    super(sc, simulation);
    this.config = config;
  }

  async init(adminContext: SignerContext) {
    this.accountId = await seedPMRMAccount(adminContext, this.config.initialBalance, this.sc.signerAddress);
  }

  async step() {
    console.log(chalk.grey(`Trader ${this.sc.signerAddress} step`))
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
    let trades = [];
    for (let i = 0; i < this.config.numTrades; i++) {
      const boardId = allBoards[Math.floor(Math.random() * allBoards.length)];
      // random number between tradeSize params
      const tradeSize = (Math.random() * (+this.config.tradeSize[1] - +this.config.tradeSize[0])) + +this.config.tradeSize[0];
      const tradeSizeBN = toBN(tradeSize.toString());
      const isBuy = Math.random() > 0.5;
      trades.push(...this.market.placeLimitOrder(boardId, {
        accountId: this.accountId,
        amount: tradeSizeBN,
        pricePerOption: isBuy ? toBN('1000000') : toBN('0'), // max bid
        collateralPerOption: isBuy ? toBN('0') : toBN('1000'),
        signature: "0x"
      }, isBuy));
    }
    console.log(trades);
  }
}