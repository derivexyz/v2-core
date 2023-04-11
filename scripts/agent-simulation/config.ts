export const config = {
  simulationSettings: {
    stepSizeSec: 93600,
    numSteps: 2,
  },
  agents: {
    marketMakerConfig: {
      num: 1,
      initialBalance: "1000000"
    },
    traderConfig: {
      num: 1,
      initialBalance: "10000",
      numTrades: 4,
      tradeSize: ["1", "10"]
    }
  }
}