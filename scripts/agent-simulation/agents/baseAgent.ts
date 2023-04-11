import {SignerContext} from "../../utils/env/signerContext";
import {Simulation} from "../simulation";
import {Market} from "../market/market";

export class BaseAgent {
  simulation: Simulation;
  market: Market;
  sc: SignerContext;
  constructor(sc: SignerContext, simulation: Simulation) {
    this.sc = sc;
    this.simulation = simulation;
    this.market = simulation.market;
  }

  async init(adminContext: SignerContext) {
    throw new Error('Not implemented');
  }

  async step() {
    throw new Error('Not implemented');
  }

  async log() {}
}