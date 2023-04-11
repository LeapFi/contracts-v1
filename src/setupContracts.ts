import { ethers } from "hardhat";
import hre = require("hardhat");
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";

export async function setupContracts(feeTier: number) {

  const [owner] = await ethers.getSigners();
  const addresses = getAddresses(hre.network.name);

  const uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
  const uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
  const swapRouter = (await ethers.getContractAt("ISwapRouter", addresses.SwapRouter)) as ISwapRouter;
  const gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GMXPositionRouter)) as IGmxPositionRouter;
  const gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GMXFastPriceFeed)) as IGmxFastPriceFeed;
  const weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  const usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;

  const UniHelper = await ethers.getContractFactory("UniHelper");
  const uniHelper = await UniHelper.deploy(addresses.UniswapV3Factory);

  const DerivioAStorage = await ethers.getContractFactory("DerivioAStorage");
  const derivioAStorage = await DerivioAStorage.deploy();

  const DerivioA = await ethers.getContractFactory("DerivioA");
  const derivioA = await DerivioA.deploy(
    uniHelper.address,
    addresses.UniswapV3Factory,
    addresses.SwapRouter,
    addresses.NonfungiblePositionManager,
    addresses.GMXPositionRouter,
    addresses.GMXRouter,
    addresses.GMXVault,
    weth.address,
    usdc.address,
    false
  );

  const PositionRouter = await ethers.getContractFactory("PositionRouter")
  const positionRouter = await PositionRouter.deploy(derivioAStorage.address)
  await positionRouter.addDerivioAPair(
    uniHelper.address,
    addresses.UniswapV3Factory,
    addresses.SwapRouter,
    addresses.NonfungiblePositionManager,
    addresses.GMXPositionRouter,
    addresses.GMXRouter,
    addresses.GMXVault,
    weth.address,
    usdc.address,
    false
  );

  return {
    owner,
    addresses,
    uniswapV3Factory,
    uniswapV3Pool,
    swapRouter,
    gmxPositionRouter,
    gmxFastPriceFeed,
    weth,
    usdc,
    uniHelper,
    derivioA,
    positionRouter,
  };
}