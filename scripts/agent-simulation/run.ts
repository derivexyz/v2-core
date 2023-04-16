import {deployPMRM} from "../deploy/deployPMRM";
import {Simulation} from "./simulation";
import {getSignerContext, SignerContext} from "../utils/env/signerContext";
import fsExtra from "fs-extra";
import path from "path";
import hre from "hardhat";
import chalk from "chalk/index";

function getMostRecentFileName(dir) {
  const files = fsExtra.readdirSync(dir);

  let maxSeen: any = {
    time: 0,
    val: undefined
  }
  for (const file of files) {
    const fileTime = fsExtra.statSync(path.join(dir, file)).ctime;
    if (fileTime > maxSeen.time) {
      maxSeen = {
        time: fileTime,
        val: path.join(dir, file)
      }
    }
  }
  if (!maxSeen.val) {
    throw new Error("No files found in dir");
  }
  return maxSeen.val;
}

async function addCompilationResult(sc: SignerContext) {
  if (hre.network.name !== "local") {
    console.log("Skipping adding compilation result because we are not on local network");
    return;
  }
  console.log("Adding new compilation result to the node");

  const buildInfo = getMostRecentFileName(path.join(__dirname, "../../artifacts/build-info"));

  const { input, output, solcVersion } = await fsExtra.readJSON(buildInfo, {
    encoding: "utf8",
  });
  await sc.provider.send( "hardhat_addCompilationResult",
    [solcVersion, input, output]
  );
}

async function main() {
  const deployerContext = await getSignerContext();

  // console.log(chalk.green("Deploying contracts for simulation"))
  // await deployPMRM(deployerContext);
  // await addCompilationResult(deployerContext);

  const simulation = new Simulation(deployerContext);
  await simulation.init();
  await simulation.run();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
