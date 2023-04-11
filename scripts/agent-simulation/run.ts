import {deployPMRM} from "../deploy/deployPMRM";
import {Simulation} from "./simulation";
import {getSignerContext} from "../utils/env/signerContext";


async function main() {
  const deployerContext = await getSignerContext();
  // await deployPMRM(deployerContext);
  const simulation = new Simulation(deployerContext);
  await simulation.init();
  await simulation.run();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
