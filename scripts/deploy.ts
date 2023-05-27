import { ethers } from "hardhat";

async function main() {
  const SubAccounts = await ethers.getContractFactory("SubAccounts");
  const account = await SubAccounts.deploy("Lyra Protocol SubAccounts", "LPA");

  console.log(
    `SubAccounts deployed to ${account.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
