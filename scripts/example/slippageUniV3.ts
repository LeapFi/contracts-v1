import hre = require("hardhat");
import { ethers } from "hardhat";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  IPositionRouter,
  DerivioPositionManager,
} from "../../typechain";
import { getPositionsInfos } from "../../src/position";


async function main(): Promise<void> {
  const feeTier = 500;

  const addresses = getAddresses(hre.network.name);
  const [owner] = await ethers.getSigners();
  const userAddr = owner.address;

  const uniswapV3Factory = await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory) as IUniswapV3Factory;
  const uniswapV3Pool = await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier)) as IUniswapV3Pool;
  const weth = await ethers.getContractAt("IERC20", addresses.WETH) as IERC20;
  const usdc = await ethers.getContractAt("IERC20", addresses.USDC) as IERC20;
  const positionRouter = await ethers.getContractAt("IPositionRouter", addresses.LeapPositionRouter) as IPositionRouter;
  const derivioPositionManager = await ethers.getContractAt("DerivioPositionManager", addresses.DerivioPositionManager) as DerivioPositionManager;

  const { tick: currentTick } = await uniswapV3Pool.slot0();
  const tickSpacing = await uniswapV3Pool.tickSpacing();

  const lowerTick = currentTick - (currentTick % tickSpacing) - 25 * tickSpacing;
  const upperTick = currentTick - (currentTick % tickSpacing) + 10 * tickSpacing;

  await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
  await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);

  const valueInput = ethers.utils.parseUnits("0", 18);
  const slot0 = await uniswapV3Pool.slot0();

  // Open DerivioAS
  const positionParams = [{
    recipient: userAddr,
    tickLower: lowerTick,
    tickUpper: upperTick,
    feeTier: feeTier,
    amount0Desired: 0,
    amount1Desired: ethers.utils.parseUnits("1000", 6),
    shortLeverage: 0,
    swapSqrtPriceLimitX96: slot0.sqrtPriceX96, // Will be reverted due to slippage
    shortPriceLimit: 0,
  }];
  await positionRouter.openDerivioAPositions(positionParams, weth.address, usdc.address, { value: valueInput });
  console.log('Open AS done.');

  console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});
