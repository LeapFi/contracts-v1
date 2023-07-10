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
  DerivioA,
  DerivioFuture,
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

  const OrderManager = await ethers.getContractFactory("OrderManager");
  const orderManager = await OrderManager.deploy(weth.address);
  
  const UniV3Manager = await ethers.getContractFactory("UniV3Manager");
  const uniV3Manager = await UniV3Manager.deploy(
    addresses.UniswapV3Factory,
    weth.address,
    usdc.address,
  );

  const GmxManager = await ethers.getContractFactory("GmxManager");
  const gmxManager = await GmxManager.deploy(
    gmxPositionRouter.address,
    addresses.GmxRouter,
    addresses.GmxVault,
  );
  
  const PositionRouter = await ethers.getContractFactory("PositionRouter");
  const positionRouter = await PositionRouter.deploy(
    derivioAFactory.address, 
    uniHelper.address,
    addresses.UniswapV3Factory,
    addresses.SwapRouter,
    derivioPositionManager.address,
    orderManager.address,
    uniV3Manager.address,
    gmxManager.address
  );

  await positionRouter.addDerivioAPair(
    weth.address,
    usdc.address,
    false
  );

  await positionRouter.addDerivioFuturePair(
    usdc.address,
    weth.address
  );
  
  const derivioAAdress = await positionRouter.getDerivioAContract(0, weth.address, usdc.address);
  const derivioA = (await ethers.getContractAt("DerivioA", derivioAAdress)) as DerivioA;

  const derivioFutureAddress = await positionRouter.getDerivioFutureContract(1, usdc.address, weth.address);
  const derivioFuture = (await ethers.getContractAt("DerivioFuture", derivioFutureAddress)) as DerivioFuture;

  await derivioA.setLiquidator(owner.address, true);
  await derivioPositionManager.setManager(derivioA.address, true);
  await derivioPositionManager.setManager(derivioFuture.address, true);

  // DerivioA keeper fee
  await orderManager.setKeeperFee(0, ethers.utils.parseUnits("0.0001", 18));
  // DerivioFuture keeper fee
  await orderManager.setKeeperFee(1, ethers.utils.parseUnits("0.00003", 18));

  await orderManager.setManager(positionRouter.address, true);
  await orderManager.setManager(derivioA.address, true);

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
    orderManager,
    gmxManager,
    uniV3Manager,
  };
}