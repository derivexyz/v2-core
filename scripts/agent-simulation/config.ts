export const config = {
  simulationSettings: {
    stepSizeSec: 3600,
    numSteps: 10,
  },
  agents: {
    marketMakerConfig: {
      num: 2,
      initialBalance: "100000000"
    },
    traderConfig: {
      num: 10,
      initialBalance: "100000000",
      numTrades: 20,
      tradeSize: ["0.1", "1"]
    }
  }
}