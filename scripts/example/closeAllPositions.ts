import hre = require("hardhat");
import { ethers } from "hardhat";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  DerivioPositionManager,
  IPositionRouter,
} from "../../typechain";
import { getPositionsInfos, closeAllPositions } from "../../src/position";

async function main(): Promise<void> {

  const addresses = getAddresses(hre.network.name);
  const [owner] = await ethers.getSigners();
  const userAddr = owner.address;

  const weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  const usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
  const positionRouter = (await ethers.getContractAt("IPositionRouter", addresses.LeapPositionRouter)) as IPositionRouter;
  const derivioPositionManager = await ethers.getContractAt("DerivioPositionManager", addresses.DerivioPositionManager) as DerivioPositionManager;

  // Close all positions in user
  await closeAllPositions(positionRouter, derivioPositionManager, owner.address, weth.address, usdc.address);
  
  console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});

