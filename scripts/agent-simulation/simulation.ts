import {BaseAgent} from "./agents/baseAgent";
import {Market} from "./market/market";
import {SignerContext, getSignerContext} from "../utils/env/signerContext";
import {config} from "./config";
import {MarketMakerAgent} from "./agents/marketMaker";
import {TraderAgent} from "./agents/trader";
import chalk from "chalk";
import {fastForward} from "../utils/test";
import {executeExternalFunction} from "../utils/contracts/transactions";
import {BigNumber} from "ethers";
import {toBN} from "../utils";
import hre from "hardhat";

type SimulationConfig = {
  stepSizeSec: number;
  numSteps: number;
}

const DEFAULT_SPOT = toBN("1000");


export class Simulation {
  adminContext: SignerContext;
  config: SimulationConfig;
  agents: BaseAgent[] = [];
  market: Market;
  currentStep: number = 1;
  currentTime: number;
  spotPrice: BigNumber;

  constructor(adminContext: SignerContext) {
    this.adminContext = adminContext;
    this.config = config.simulationSettings;
  }

  async init() {
    await this.updateCurrentTime();

    this.market = new Market(this.adminContext, this);

    let signerCount = 1;
    for (let i=0; i<config.agents.marketMakerConfig.num; i++) {
      const mmAgent = new MarketMakerAgent(await getSignerContext(signerCount++), this, config.agents.marketMakerConfig);
      this.agents.push(mmAgent);
    }
    for (let i=0; i<config.agents.traderConfig.num; i++) {
      const traderAgent = new TraderAgent(await getSignerContext(signerCount++), this, config.agents.traderConfig);
      this.agents.push(traderAgent);
    }
    // TODO: liquidator agent

    for (let agent of this.agents) {
      await agent.init(this.adminContext);
    }

    await this.waitForAllTransactions();
  }

  async run() {
    while (this.currentStep <= this.config.numSteps) {
      await this._step();
      // await this._log();
      this.currentStep++;
      await this.skipTime();
    }
  }

  async _step() {
    const startTime = Date.now();

    console.log(chalk.magenta(`Running step ${this.currentStep} of ${this.config.numSteps}`));

    await this._setFeeds();
    await this.market.step();
    for (let agent of this.agents) {
      await agent.step();
    }

    await this.waitForAllTransactions();

    const endTime = Date.now();
    console.log(chalk.magenta(`Step ${this.currentStep} of ${this.config.numSteps} took ${endTime - startTime} ms`));
  }

  async _log() {
    console.log(chalk.magenta(`Logging step ${this.currentStep} of ${this.config.numSteps}`));
    await this.market.log();
    for (let agent of this.agents) {
      await agent.log();
    }
  }

  async _setFeeds() {
    this.spotPrice = DEFAULT_SPOT.add(toBN(this.currentStep.toString()));
    await executeExternalFunction(this.adminContext, "ETH_SpotFeed", 'setSpot', [this.spotPrice]);
  }

  async updateCurrentTime() {
    this.currentTime = (await this.adminContext.provider.getBlock('latest')).timestamp;
  }

  async getSpotPrice() {
    return this.spotPrice;
  }

  async getRate() {
    return toBN('0.05');
  }

  async getVol(boardId: string) {
    return toBN('0.6');
  }

  async waitForAllTransactions() {
    for (let agent of this.agents) {
      await agent.waitForPendingTxs();
    }
  }

  async skipTime() {
    if (hre.network.name !== "local") {
      console.log(chalk.yellow("warning: Skipping time is only supported on local network"));
      return;
    }
    const seconds = this.config.stepSizeSec;
    await fastForward(seconds);
    await this.updateCurrentTime();
  }
}
