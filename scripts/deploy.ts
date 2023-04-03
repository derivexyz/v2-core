import { ethers } from "hardhat";

async function main() {
  const Accounts = await ethers.getContractFactory("Accounts");
  const account = await Accounts.deploy("Lyra Protocol Accounts", "LPA");

  console.log(
    `Accounts deployed to ${account.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
