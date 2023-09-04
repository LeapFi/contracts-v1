import hre = require("hardhat");
import { ethers } from "hardhat";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  IPositionRouter,
  IGmxPositionRouter,
  DerivioPositionManager,
  OrderManager
} from "../../typechain";
import { getPositionsInfos, getProductKeeperFee } from "../../src/position";

// Helper function to wait for a certain amount of time
function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// async function waitForGmxPosition(positionRouter: IPositionRouter, wethAddress: string, usdcAddress: string): Promise<void> {
//   let sizeDelta = ethers.BigNumber.from(0);
//   let collateral = ethers.BigNumber.from(0);

//   while (sizeDelta.isZero() && collateral.isZero()) {
//     console.log("Waiting for GMX position...");

//     await positionRouter.getGmxPosition(wethAddress, usdcAddress);

//     const result = await positionRouter.callStatic.getGmxPosition(wethAddress, usdcAddress);
    
//     console.log("sizeDelta: ", result.sizeDelta, "    collateral: ", result.collateral);
//     sizeDelta = result.sizeDelta;
//     collateral = result.collateral;

//     if (sizeDelta.isZero() && collateral.isZero()) {
//       await delay(10000); // Wait for 10 seconds
//     }
//   }

//   console.log("GMX position created");
// }

async function main(): Promise<void> {
  const feeTier = 500;

  const addresses = getAddresses(hre.network.name);
  const [owner] = await ethers.getSigners();
  const userAddr = owner.address;

  const uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
  const uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
  const gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GmxPositionRouter)) as IGmxPositionRouter;
  const weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  const usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
  const positionRouter = (await ethers.getContractAt("IPositionRouter", addresses.LeapPositionRouter)) as IPositionRouter;
  const derivioPositionManager = await ethers.getContractAt("DerivioPositionManager", addresses.DerivioPositionManager) as DerivioPositionManager;
  const orderManager = await ethers.getContractAt("OrderManager", addresses.OrderManager) as OrderManager;

  const { tick: currentTick } = await uniswapV3Pool.slot0();
  const tickSpacing = await uniswapV3Pool.tickSpacing();

  const lowerTick = currentTick - (currentTick % tickSpacing) - 25 * tickSpacing;
  const upperTick = currentTick - (currentTick % tickSpacing) + 10 * tickSpacing;

  await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
  await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);

  const keeperFee = await getProductKeeperFee(orderManager, gmxPositionRouter, 0);
  
  // Open DerivioAL
  const positionParams = [{
    recipient: userAddr,
    transferFromRecipient: true,
    tickLower: lowerTick,
    tickUpper: upperTick,
    feeTier: feeTier,
    amount0Desired: 0,
    amount1Desired: ethers.utils.parseUnits("1000", 6),
    shortLeverage: 50e6,
    swapSqrtPriceLimitX96: 0,
    shortPriceLimit: 0,
  }];
  await positionRouter.openDerivioAPositions(positionParams, weth.address, usdc.address, { value: keeperFee, gasLimit: "99999999999" });

  // Get all positions in user
  console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});

