import { ethers } from "hardhat";
import hre = require("hardhat");
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxPositionManager,
  IGmxFastPriceFeed,
  IGmxPriceFeed,
  IGmxVault,
  UniV3Manager,
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";

export async function setupContracts(feeTier: number) {

  const [owner] = await ethers.getSigners();
  const addresses = getAddresses(hre.network.name);

  const uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
  const uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
  const swapRouter = (await ethers.getContractAt("ISwapRouter", addresses.SwapRouter)) as ISwapRouter;
  const gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GmxPositionRouter)) as IGmxPositionRouter;
  const gmxPositionManager = (await ethers.getContractAt("IGmxPositionManager", addresses.GmxPositionManager)) as IGmxPositionManager;
  const gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GmxFastPriceFeed)) as IGmxFastPriceFeed;
  const gmxEthPriceFeed = (await ethers.getContractAt("IGmxPriceFeed", addresses.GmxEthPriceFeed)) as IGmxPriceFeed;
  const gmxVault = (await ethers.getContractAt("IGmxVault", addresses.GmxVault)) as IGmxVault;
  const weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  const usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;

  const UniHelper = await ethers.getContractFactory("UniHelper");
  const uniHelper = await UniHelper.deploy(addresses.UniswapV3Factory);

  const DerivioAFactory = await ethers.getContractFactory("DerivioAFactory");
  const derivioAFactory = await DerivioAFactory.deploy();
  
  const DerivioPositionManager = await ethers.getContractFactory("DerivioPositionManager");
  const derivioPositionManager = await DerivioPositionManager.deploy();

  const UniV3Manager = await ethers.getContractFactory("UniV3Manager");
  const uniV3Manager = await UniV3Manager.deploy(
    addresses.UniswapV3Factory,
    addresses.SwapRouter,
    weth.address,
    usdc.address,
  );

  const GmxManager = await ethers.getContractFactory("GmxManager");
  const gmxManager = await GmxManager.deploy(
    gmxPositionRouter.address,
    addresses.GmxRouter,
    addresses.GmxVault,
  );

  const DerivioA = await ethers.getContractFactory("DerivioA");
  const derivioA = await DerivioA.deploy(
    uniHelper.address,
    uniswapV3Factory.address,
    swapRouter.address,
    derivioPositionManager.address,
    uniV3Manager.address,
    gmxManager.address,
    weth.address,
    usdc.address,
    false
  );

  const PositionRouter = await ethers.getContractFactory("PositionRouter");
  const positionRouter = await PositionRouter.deploy(derivioAFactory.address, derivioPositionManager.address);
  await positionRouter.addDerivioAPair(
    uniHelper.address,
    addresses.UniswapV3Factory,
    addresses.SwapRouter,
    derivioPositionManager.address,
    uniV3Manager.address,
    gmxManager.address,
    weth.address,
    usdc.address,
    false
  );

  await positionRouter.addDerivioFuturePair(
    derivioPositionManager.address,
    gmxManager.address,
    usdc.address,
    weth.address
  );

  return {
    owner,
    addresses,
    uniswapV3Factory,
    uniswapV3Pool,
    swapRouter,
    gmxPositionRouter,
    gmxPositionManager,
    gmxFastPriceFeed,
    gmxEthPriceFeed,
    gmxVault,
    weth,
    usdc,
    uniHelper,
    derivioA,
    derivioPositionManager,
    positionRouter,
    gmxManager,
    uniV3Manager,
  };
}