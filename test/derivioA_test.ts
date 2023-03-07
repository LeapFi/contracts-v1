// import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { getAddresses, Addresses } from "../src/addresses";
import hre = require("hardhat");
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
} from "../typechain";
import { Signer } from "ethers";
import { fundErc20 } from "../src/fundErc20";
import { swap } from "../src/swap";

// export async function constructPosition(
//   token0Amount: CurrencyAmount<Token>,
//   token1Amount: CurrencyAmount<Token>
// ): Promise<Position> {
//   // get pool info
//   const poolInfo = await getPoolInfo()

//   // construct pool instance
//   const configuredPool = new Pool(
//     token0Amount.currency,
//     token1Amount.currency,
//     poolInfo.fee,
//     poolInfo.sqrtPriceX96.toString(),
//     poolInfo.liquidity.toString(),
//     poolInfo.tick
//   )

//   // create position using the maximum liquidity from input amounts
//   return Position.fromAmounts({
//     pool: configuredPool,
//     tickLower:
//       nearestUsableTick(poolInfo.tick, poolInfo.tickSpacing) -
//       poolInfo.tickSpacing * 2,
//     tickUpper:
//       nearestUsableTick(poolInfo.tick, poolInfo.tickSpacing) +
//       poolInfo.tickSpacing * 2,
//     amount0: token0Amount.quotient,
//     amount1: token1Amount.quotient,
//     useFullPrecision: true,
//   })
// }

describe("DerivioA test", function () {
  
  let owner: Signer;
  let otherAccount: Signer;
  let uniswapV3Pool: IUniswapV3Pool;
  let uniswapV3Factory: IUniswapV3Factory;
  let swapRouter: ISwapRouter;
  let lowerTick: number;
  let upperTick: number;

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployContracts() {

    let addresses = getAddresses(hre.network.name);
    let feeTier = 500;

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount] = await ethers.getSigners();

    uniswapV3Factory = (await ethers.getContractAt(
      "IUniswapV3Factory",
      addresses.UniswapV3Factory,
      owner
    )) as IUniswapV3Factory;

    uniswapV3Pool = (await ethers.getContractAt(
      "IUniswapV3Pool",
      await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier),
      owner
    )) as IUniswapV3Pool;

    swapRouter = (await ethers.getContractAt(
      "ISwapRouter",
      addresses.SwapRouter,
      owner
    )) as ISwapRouter;

    const weth = (await ethers.getContractAt(
      "IERC20",
      addresses.WETH,
      owner
    )) as IERC20;

    const usdc = (await ethers.getContractAt(
      "IERC20",
      addresses.USDC,
      owner
    )) as IERC20;

    const UniHelper = await ethers.getContractFactory("UniHelper");
    const uniHelper = await UniHelper.deploy(addresses.UniswapV3Factory);

    const DerivioA = await ethers.getContractFactory("DerivioA");
    const derivioA = await DerivioA.deploy(
      uniHelper.address,
      addresses.UniswapV3Factory,
      addresses.SwapRouter,
      addresses.NonfungiblePositionManager,
      weth.address,
      usdc.address
    );

    const slot0 = await uniswapV3Pool.slot0();
    const tickSpacing = await uniswapV3Pool.tickSpacing();

    lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 20 * tickSpacing;
    upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
    
    console.log('Balance: ', await ethers.provider.getBalance(owner.address))
    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    
    console.log("usdc: " + await usdc.balanceOf(addresses.USDCWhale))
    await fundErc20(usdc, addresses.USDCWhale, owner.address, 10000000, 6);
      
    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    
    await swap(swapRouter, owner, usdc, weth, 100, 6);

    console.log('Balance: ', await ethers.provider.getBalance(owner.address))
    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    
    await weth.approve(derivioA.address, ethers.constants.MaxUint256);
    await usdc.approve(derivioA.address, ethers.constants.MaxUint256);
    await derivioA.openPosition(
      lowerTick,
      upperTick,
      feeTier,
      0,
      ethers.utils.parseUnits("1000", 6),
      0,
    );

    let a = 1
  }

  describe("Deployment", function () {
    it("#1 Should normally deployed contracts", async function () {
      await deployContracts();
    });
  });

});
