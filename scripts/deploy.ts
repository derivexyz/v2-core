import {getDeploymentContext} from "./env/deploymentContext";
import {deploySystem} from "./deploy/deploySystem";

async function main() {
  const dc = getDeploymentContext();
  await deploySystem(dc);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
