import {BaseAgent} from "./baseAgent";
import {SignerContext} from "../../utils/env/signerContext";
import {seedPMRMAccount} from "../../seed/seedPMRMAccount";
import {BigNumber} from "ethers";
import chalk from "chalk";
import {Simulation} from "../simulation";
import {getOptionParams} from "../../utils/options/optionEncoding";
import {callPrice, optionPrices, putPrice, tAnnualised} from "../../utils/options/blackScholes";
import {fromBN, toBN} from "../../utils";

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
        this.market.placeLimitOrder(
          boardId,
          {
            accountId: this.accountId,
            amount: toBN('5'),
            pricePerOption: toBN((bsPrice).toString()).mul(99 - step).div(100), // 95% of mark price
            collateralPerOption: toBN('0'),
            signature: "0x"
          },
          true
        )

        this.market.placeLimitOrder(
          boardId,
          {
            accountId: this.accountId,
            amount: toBN('5'),
            pricePerOption: toBN((bsPrice).toString()).mul(101 + step).div(100), // 105% of mark price
            collateralPerOption: toBN('1000'),
            signature: "0x"
          },
          false
        )
      }
    }
  }
}