// import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import hre = require("hardhat");
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import { BigNumber as EthersBigNumber } from "@ethersproject/bignumber"
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
} from "../typechain";
import { Signer } from "ethers";
import { getAddresses, Addresses } from "../src/addresses";
import { fundErc20 } from "../src/fundErc20";
import { swap } from "../src/swap";
import { executeIncrease, setPricesWithBitsAndExecute } from "../src/executeGmxPosition";
import { getPriceBits } from "../src/utilities";

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

export async function getBlockTime(): Promise<number> {
  const block = await ethers.provider.getBlock('latest')
  return block.timestamp
}

export function toWei(n: string): EthersBigNumber {
  return ethers.utils.parseEther(n)
}


describe("DerivioA test", function () {
  
  let feeTier = 500;
  
  let owner: Signer;
  let otherAccount: Signer;
  let lowerTick: number;
  let upperTick: number;
  let addresses = getAddresses(hre.network.name);

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployContracts() {

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount] = await ethers.getSigners();

    const uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
    const uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
    const swapRouter = (await ethers.getContractAt("ISwapRouter", addresses.SwapRouter)) as ISwapRouter;
    const gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GMXPositionRouter)) as IGmxPositionRouter;
    const gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GMXFastPriceFeed)) as IGmxFastPriceFeed;
    const weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
    const usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
    
    const UniHelper = await ethers.getContractFactory("UniHelper")
    const uniHelper = await UniHelper.deploy(addresses.UniswapV3Factory)

    const DerivioA = await ethers.getContractFactory("DerivioA")
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
    )

    const slot0 = await uniswapV3Pool.slot0()
    const tickSpacing = await uniswapV3Pool.tickSpacing()

    lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 25 * tickSpacing
    upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing
    
    // console.log('Balance: ', await ethers.provider.getBalance(owner.address))
    // console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    
    // console.log("usdc: " + await usdc.balanceOf(addresses.USDCWhale))
    await fundErc20(usdc, addresses.USDCWhale, owner.address, 10000000, 6)
      
    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    
    await swap(swapRouter, owner, usdc, weth, 100, 6)

    console.log('Balance: ', await ethers.provider.getBalance(owner.address))
    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    
    await weth.approve(derivioA.address, ethers.constants.MaxUint256)
    await usdc.approve(derivioA.address, ethers.constants.MaxUint256)
    
    const args: DerivioA.PositionArgsStruct = {
      recipient: owner.address,
      tickLower: lowerTick,
      tickUpper: upperTick,
      feeTier: feeTier,
      amount0Desired: 0,
      amount1Desired: ethers.utils.parseUnits("1000", 6),
      shortRatio: 500000,
    };

    await derivioA.openPosition(args, {value: ethers.utils.parseUnits("0.02", 18)})

    // await derivioA.openGMXShort2(
    //   ethers.utils.parseUnits("10", 6),
    //   ethers.utils.parseUnits("50", 30),
    //   0,
    //   {value: ethers.utils.parseUnits("0.02", 18)}
    // )
    
    // set price updater
    const priceGovAddress = await gmxFastPriceFeed.gov()
    await setBalance(priceGovAddress, ethers.utils.parseUnits("1000", 30))
    const priceGov = await ethers.getImpersonatedSigner(priceGovAddress)
    await gmxFastPriceFeed.connect(priceGov).setUpdater(owner.address, true)

    // fill
    const blockTime = await getBlockTime()
    const priceBits = getPriceBits([])
    await setPricesWithBitsAndExecute(gmxFastPriceFeed, owner.address, priceBits, blockTime);

    await derivioA.getGmxPosition()
    // console.log(await derivioA.positionsOf(owner.address))
    let a = 1
  }

  describe("Deployment", function () {
    it("#1 Should normally deployed contracts", async function () {
      await deployContracts();
    });
  });

});
