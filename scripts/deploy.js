// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat");

async function main() {

  // const usdt = await hre.ethers.deployContract("MockToken", ["USDT"]);
  // await usdt.waitForDeployment();
  // console.log(`USDT deployed to ${usdt.target}`);

  let usdt = {target: "0xf2d20C24314C0147D9bDA97F0Cf0BbA7A7e3afda"};
  
  const athena = await hre.ethers.deployContract("Athena", [usdt.target]);
  await athena.waitForDeployment();
  console.log(`Athena deployed to ${athena.target}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
