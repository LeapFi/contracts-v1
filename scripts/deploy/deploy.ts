import { ethers } from "hardhat";
import hre = require("hardhat");
import { Signer } from "ethers";
import { ContractFactory, Contract } from "ethers";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
  DerivioAStorage,
  PositionRouter,
} from "../../typechain";


async function main(): Promise<void> {

  let feeTier = 500
  let deployer: Signer
  let otherAccount: Signer
  let uniswapV3Factory: IUniswapV3Factory
  let uniswapV3Pool: IUniswapV3Pool
  let gmxPositionRouter: IGmxPositionRouter
  let gmxFastPriceFeed: IGmxFastPriceFeed
  let weth: IERC20
  let usdc: IERC20
  let derivioA: DerivioA
  let derivioAStorage: DerivioAStorage
  let positionRouter: PositionRouter

  let addresses = getAddresses(hre.network.name);
  [deployer, otherAccount] = await ethers.getSigners();

  uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
  uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
  gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GMXPositionRouter)) as IGmxPositionRouter;
  gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GMXFastPriceFeed)) as IGmxFastPriceFeed;
  weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;


  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  const UniHelper: ContractFactory = await ethers.getContractFactory("UniHelper");
  const uniHelper: Contract = await UniHelper.deploy(addresses.UniswapV3Factory);

  const DerivioAStorage = await ethers.getContractFactory("DerivioAStorage")
  derivioAStorage = await DerivioAStorage.deploy()

  const DerivioA = await ethers.getContractFactory("DerivioA")
  derivioA = await DerivioA.deploy(
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
  )

  const PositionRouter = await ethers.getContractFactory("PositionRouter")
  positionRouter = await PositionRouter.deploy(derivioAStorage.address)
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
  )
  console.log("PositionRouter address:", positionRouter.address);
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });