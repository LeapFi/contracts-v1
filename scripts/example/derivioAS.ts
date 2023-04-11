import hre = require("hardhat");
import { ethers } from "hardhat";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  IPositionRouter,
} from "../../typechain";


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

  const { tick: currentTick } = await uniswapV3Pool.slot0();
  const tickSpacing = await uniswapV3Pool.tickSpacing();

  const lowerTick = currentTick - (currentTick % tickSpacing) - 25 * tickSpacing;
  const upperTick = currentTick - (currentTick % tickSpacing) + 10 * tickSpacing;

  await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
  await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);

  // Open DerivioAS
  const positionParams = {
    recipient: userAddr,
    tickLower: lowerTick,
    tickUpper: upperTick,
    feeTier: feeTier,
    amount0Desired: 0,
    amount1Desired: ethers.utils.parseUnits("100", 6),
    shortLeverage: 0,
    swapMaxSlippage: 0,
    shortMaxSlippage: 0,
  };
  await positionRouter.openDerivioA(positionParams, weth.address, usdc.address);

  // Get all positions in user
  const positions = await positionRouter.positionsOf(userAddr);

  // Close all positions in user
  const positionKeysArray = positions.map((position) => position.positionKey);
  await positionRouter.closeDerivioA(positionKeysArray, weth.address, usdc.address);

  const newPositions = await positionRouter.positionsOf(userAddr);

  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
  console.log(positions);
  console.log(newPositions);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});