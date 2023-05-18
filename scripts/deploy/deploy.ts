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
  DerivioAFactory,
  PositionRouter,
} from "../../typechain";


async function main(): Promise<void> {

  let feeTier = 500;
  let deployer: Signer;
  let otherAccount: Signer;
  let uniswapV3Factory: IUniswapV3Factory;
  let uniswapV3Pool: IUniswapV3Pool;
  let swapRouter: ISwapRouter;
  let gmxPositionRouter: IGmxPositionRouter;
  let gmxFastPriceFeed: IGmxFastPriceFeed;
  let weth: IERC20;
  let usdc: IERC20;
  let derivioA: DerivioA;
  let derivioAFactory: DerivioAFactory;
  let positionRouter: PositionRouter;

  let addresses = getAddresses(hre.network.name);
  [deployer, otherAccount] = await ethers.getSigners();

  uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
  uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
  swapRouter = (await ethers.getContractAt("ISwapRouter", addresses.SwapRouter)) as ISwapRouter;
  gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GMXPositionRouter)) as IGmxPositionRouter;
  gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GMXFastPriceFeed)) as IGmxFastPriceFeed;
  weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;


  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  const UniHelper: ContractFactory = await ethers.getContractFactory("UniHelper");
  const uniHelper: Contract = await UniHelper.deploy(addresses.UniswapV3Factory);

  const DerivioAFactory = await ethers.getContractFactory("DerivioAFactory");
  derivioAFactory = await DerivioAFactory.deploy();

  const DerivioPositionManager = await ethers.getContractFactory("DerivioPositionManager");
  const derivioPositionManager = await DerivioPositionManager.deploy();
  console.log("DerivioPositionManager address:", derivioPositionManager.address);

  const UniV3Manager = await ethers.getContractFactory("UniV3Manager");
  const uniV3Manager = await UniV3Manager.deploy(
    addresses.UniswapV3Factory,
    addresses.SwapRouter,
    weth.address,
    usdc.address,
  );
  console.log("UniV3Manager address:", uniV3Manager.address);

  const GmxManager = await ethers.getContractFactory("GmxManager");
  const gmxManager = await GmxManager.deploy(
    gmxPositionRouter.address,
    addresses.GMXRouter,
    addresses.GMXVault,
  );
  console.log("GmxManager address:", gmxManager.address);

  const DerivioA = await ethers.getContractFactory("DerivioA");
  derivioA = await DerivioA.deploy(
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
  positionRouter = await PositionRouter.deploy(derivioAFactory.address, derivioPositionManager.address)
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
  console.log("PositionRouter address:", positionRouter.address);
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });