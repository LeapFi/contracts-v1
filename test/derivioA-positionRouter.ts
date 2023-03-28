// import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import hre = require("hardhat");
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
  DerivioAStorage,
  PositionRouter,
} from "../typechain";
import { Signer } from "ethers";
import { getAddresses, Addresses } from "../src/addresses";
import { fundErc20 } from "../src/fundErc20";
import { swap } from "../src/swap";
import { setPricesWithBitsAndExecute } from "../src/executeGmxPosition";

describe("DerivioA test", function () {
  
  let feeTier = 500;
  
  let owner: any;
  let otherAccount: any;
  let lowerTick: number;
  let upperTick: number;
  let addresses = getAddresses(hre.network.name);
  let uniswapV3Factory: IUniswapV3Factory;
  let uniswapV3Pool: IUniswapV3Pool;
  let swapRouter: ISwapRouter;
  let gmxPositionRouter: IGmxPositionRouter;
  let gmxFastPriceFeed: IGmxFastPriceFeed;
  let weth: IERC20;
  let usdc: IERC20;
  let derivioA: DerivioA;
  let derivioAStorage: DerivioAStorage;
  let positionRouter: PositionRouter;

  // Reuse the same setup in every test.
  beforeEach("Setting contracts", async function () {

    // Contracts are deployed using the first signer/account by default
    [owner, otherAccount] = await ethers.getSigners();

    uniswapV3Factory = (await ethers.getContractAt("IUniswapV3Factory", addresses.UniswapV3Factory)) as IUniswapV3Factory;
    uniswapV3Pool = (await ethers.getContractAt("IUniswapV3Pool", await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, feeTier))) as IUniswapV3Pool;
    swapRouter = (await ethers.getContractAt("ISwapRouter", addresses.SwapRouter)) as ISwapRouter;
    gmxPositionRouter = (await ethers.getContractAt("IGmxPositionRouter", addresses.GMXPositionRouter)) as IGmxPositionRouter;
    gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GMXFastPriceFeed)) as IGmxFastPriceFeed;
    weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
    usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
    
    const UniHelper = await ethers.getContractFactory("UniHelper");
    const uniHelper = await UniHelper.deploy(addresses.UniswapV3Factory);

    const DerivioAStorage = await ethers.getContractFactory("DerivioAStorage");
    derivioAStorage = await DerivioAStorage.deploy();

    const DerivioA = await ethers.getContractFactory("DerivioA");
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
    );

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
    );
  });

  describe("PositionRouter control flow", function () {

    it("#1 open DerivioAS by Position Router", async function () {
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 250 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 100 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
      await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      
      await positionRouter.openDerivioA(
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

      console.log(await positionRouter.positionsOf(owner.address));
    });

    it("#2 open DerivioAL by Position Router", async function () {
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 250 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 100 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
      await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      
      await positionRouter.openDerivioA(
        {
          recipient: owner.address,
          tickLower: lowerTick,
          tickUpper: upperTick,
          feeTier: feeTier,
          amount0Desired: 0,
          amount1Desired: ethers.utils.parseUnits("1000", 6),
          shortLeverage: 500000,
          swapMaxSlippage: 0,
          shortMaxSlippage: 0,
        },
        weth.address,
        usdc.address,
        {value: ethers.utils.parseUnits("0.02", 18)}
      );

      await setPricesWithBitsAndExecute(owner.address, gmxFastPriceFeed, 1700, true, 1);
      console.log(await positionRouter.positionsOf(owner.address));
    });

    it("#3 close DerivioAS by Position Router", async function () {
      
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 250 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 100 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
      await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))

      await positionRouter.openDerivioA(
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
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))

      const positionKeys = await positionRouter.positionsOf(owner.address);
      await positionRouter.closeDerivioA([positionKeys[0].positionKey], weth.address, usdc.address);
      const newPositionKeys = await positionRouter.positionsOf(owner.address);
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))

      expect(newPositionKeys.length).to.equal(positionKeys.length - 1);
    });

    it("#4 close DerivioAL by Position Router", async function () {
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 250 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 100 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
      await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
      
      await positionRouter.openDerivioA(
        {
          recipient: owner.address,
          tickLower: lowerTick,
          tickUpper: upperTick,
          feeTier: feeTier,
          amount0Desired: 0,
          amount1Desired: ethers.utils.parseUnits("1000", 6),
          shortLeverage: 500000,
          swapMaxSlippage: 0,
          shortMaxSlippage: 0,
        },
        weth.address,
        usdc.address,
        {value: ethers.utils.parseUnits("0.02", 18)}
      );
      
      const positionKeys = await positionRouter.positionsOf(owner.address);
      await positionRouter.closeDerivioA([positionKeys[0].positionKey], weth.address, usdc.address, {value: ethers.utils.parseUnits("0.0001", 18)});
      await setPricesWithBitsAndExecute(owner.address, gmxFastPriceFeed, false, 1500, 1);
      const newPositionKeys = await positionRouter.positionsOf(owner.address);

      expect(newPositionKeys.length).to.equal(positionKeys.length - 1);
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      await positionRouter.getGmxPosition(weth.address, usdc.address);
    });

  });

});
