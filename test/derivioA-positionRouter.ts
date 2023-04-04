import { expect } from "chai";
import { ethers } from "hardhat";
import hre = require("hardhat");
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
  PositionRouter,
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";
import { setupContracts } from "../src/setupContracts";
import { fundErc20 } from "../src/fundErc20";
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
  let positionRouter: PositionRouter;
  let contracts: any;

  // Reuse the same setup in every test.
  beforeEach("Setting contracts", async function () {

    // Contracts are deployed using the first signer/account by default
    [owner, otherAccount] = await ethers.getSigners(); 
    contracts = await setupContracts(feeTier);
    uniswapV3Pool = contracts.uniswapV3Pool;
    swapRouter = contracts.swapRouter;
    gmxPositionRouter = contracts.gmxPositionRouter;
    gmxFastPriceFeed = contracts.gmxFastPriceFeed;
    weth = contracts.weth;
    usdc = contracts.usdc;
    derivioA = contracts.derivioA;
    weth = contracts.weth;
    weth = contracts.weth;
    weth = contracts.weth;
    positionRouter = contracts.positionRouter;
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

      // await setPricesWithBitsAndExecute(owner.address, gmxFastPriceFeed, 1700, true, 1);
      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
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
      // await setPricesWithBitsAndExecute(owner.address, gmxFastPriceFeed, false, 1500, 1);
      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);

      const newPositionKeys = await positionRouter.positionsOf(owner.address);
      expect(newPositionKeys.length).to.equal(positionKeys.length - 1);
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      await positionRouter.getGmxPosition(weth.address, usdc.address);
    });

  });

});
