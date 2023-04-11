import {getSignerContext} from "./utils/env/signerContext";
import {deployPMRM} from "./deploy/deployPMRM";
import {seedPMRMAccount} from "./seed/seedPMRMAccount";

async function main() {
  const sc = await getSignerContext();
  const account1 = await seedPMRMAccount(sc);
  const account2 = await seedPMRMAccount(sc);
  console.log({account1, account2})
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
