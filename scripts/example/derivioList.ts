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

async function main(): Promise<void> {

  const feeTier = 500;

  const addresses = getAddresses(hre.network.name);
  const [owner] = await ethers.getSigners();
  const userAddr = owner.address;

  const weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  const usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
  const uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
  const uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
  const gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GmxPositionRouter)) as IGmxPositionRouter;
  const positionRouter = (await ethers.getContractAt("IPositionRouter", addresses.LeapPositionRouter)) as IPositionRouter;
  const derivioPositionManager = await ethers.getContractAt("DerivioPositionManager", addresses.DerivioPositionManager) as DerivioPositionManager;
  const orderManager = await ethers.getContractAt("OrderManager", addresses.OrderManager) as OrderManager;

  const { tick: currentTick } = await uniswapV3Pool.slot0();
  const tickSpacing = await uniswapV3Pool.tickSpacing();
  const lowerTick = currentTick - (currentTick % tickSpacing) - 25 * tickSpacing;
  const upperTick = currentTick - (currentTick % tickSpacing) + 10 * tickSpacing;
  
  await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
  
  const isLong = true;
  const collateralAmount = 500;
  const leverage = 2;
  const aKeeperFee = await getProductKeeperFee(orderManager, gmxPositionRouter, 0);
  const futureKeeperFee = await getProductKeeperFee(orderManager, gmxPositionRouter, 1);
  const totalKeeperFee = ethers.BigNumber.from(aKeeperFee).add(ethers.BigNumber.from(futureKeeperFee));

  const collateralAmountIn = ethers.utils.parseUnits(collateralAmount.toString(), 6);
  const sizeDelta = ethers.utils.parseUnits((collateralAmount * leverage).toString(), 6);

  
  // Parameters for DerivioA
  const positionParamsA = [{
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

  // Parameters for DerivioFuture
  const positionParamsFuture = [{
      recipient: owner.address,
      transferFromRecipient: true,
      isLong: isLong,
      collateralAmount: collateralAmountIn,
      sizeDelta: sizeDelta,
      acceptPrice: isLong ? ethers.constants.MaxUint256 : 0,
  }];

  // Call the openDerivioPositions function
  const tx = await positionRouter.openDerivioPositions(
      positionParamsA,
      weth.address,
      usdc.address,
      positionParamsFuture,
      usdc.address,
      weth.address,
      { value: totalKeeperFee, gasLimit: ethers.BigNumber.from("99999999999") }
  );
    
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

