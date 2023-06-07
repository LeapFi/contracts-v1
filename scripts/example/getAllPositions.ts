import hre = require("hardhat");
import { ethers } from "hardhat";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  DerivioPositionManager,
} from "../../typechain";
import { getPositionsInfos } from "../../src/position";


async function main(): Promise<void> {

  const addresses = getAddresses(hre.network.name);
  const [owner] = await ethers.getSigners();
  const userAddr = owner.address;

  const weth = await ethers.getContractAt("IERC20", addresses.WETH) as IERC20;
  const usdc = await ethers.getContractAt("IERC20", addresses.USDC) as IERC20;
  const derivioPositionManager = await ethers.getContractAt("DerivioPositionManager", addresses.DerivioPositionManager) as DerivioPositionManager;

  console.log("Account:", owner.address);
  console.log("Account balance:", (await owner.getBalance()).toString());
  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
  console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});
