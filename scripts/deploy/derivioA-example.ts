import { ethers } from "hardhat";
import hre = require("hardhat");
import { Signer } from "ethers";
import { ContractFactory, Contract } from "ethers";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
  DerivioAStorage,
  IPositionRouter,
} from "../../typechain";
import { fundErc20 } from "../../src/fundErc20";


async function main(): Promise<void> {

  let positionRouterAddress = '0x57AC7efDC029559852115fBF8b8a59EAfa70a543';
  let feeTier = 500;
  let owner: Signer;
  let otherAccount: Signer;
  let uniswapV3Factory: IUniswapV3Factory;
  let uniswapV3Pool: IUniswapV3Pool;
  let gmxPositionRouter: IGmxPositionRouter;
  let gmxFastPriceFeed: IGmxFastPriceFeed;
  let weth: IERC20;
  let usdc: IERC20;
  let derivioA: DerivioA;
  let derivioAStorage: DerivioAStorage;
  let iPositionRouter: IPositionRouter;

  let addresses = getAddresses(hre.network.name);
  [owner, otherAccount] = await ethers.getSigners();

  uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
  uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
  gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GMXPositionRouter)) as IGmxPositionRouter;
  gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GMXFastPriceFeed)) as IGmxFastPriceFeed;
  weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
  iPositionRouter = (await ethers.getContractAt("IPositionRouter", positionRouterAddress)) as IPositionRouter;

  const slot0 = await uniswapV3Pool.slot0();
  const tickSpacing = await uniswapV3Pool.tickSpacing();

  const lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 25 * tickSpacing;
  const upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
  
  console.log('address: ' + owner.address);
  console.log('balanceOf: ' + await usdc.balanceOf(owner.address));
  // await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6)
  // console.log('balanceOf: ' + await usdc.balanceOf(owner.address))
  
  await weth.approve(iPositionRouter.address, ethers.constants.MaxUint256)
  await usdc.approve(iPositionRouter.address, ethers.constants.MaxUint256)
  
  await iPositionRouter.openDerivioA(
    {
      recipient: owner.address,
      tickLower: lowerTick,
      tickUpper: upperTick,
      feeTier: feeTier,
      amount0Desired: 0,
      amount1Desired: ethers.utils.parseUnits("1000", 6),
      shortLeverage: 0,
      swapMaxSlippage: 0,
      shortMaxSlippage: 0,
    },
    weth.address,
    usdc.address,
  );

  // console.log(await positionRouter.getPairId(0, weth.address, usdc.address))
  // console.log(await positionRouter.positionsOf(owner.address));
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });