import hre = require("hardhat");
import { ethers } from "hardhat";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  ISwapRouter,
  DerivioPositionManager,
} from "../../typechain";
import { getPositionsInfos } from "../../src/position";
import { swap } from "../../src/swap";


async function main(): Promise<void> {
  const feeTier = 500;

  const addresses = getAddresses(hre.network.name);
  const [owner] = await ethers.getSigners();
  const userAddr = owner.address;

  const swapRouter = (await ethers.getContractAt("ISwapRouter", addresses.SwapRouter)) as ISwapRouter;
  const weth = await ethers.getContractAt("IERC20", addresses.WETH) as IERC20;
  const usdc = await ethers.getContractAt("IERC20", addresses.USDC) as IERC20;
  const derivioPositionManager = await ethers.getContractAt("DerivioPositionManager", addresses.DerivioPositionManager) as DerivioPositionManager;

  // Simulate swap fee
  await swap(swapRouter, feeTier, owner, usdc, weth, 500, 6);

  console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});
