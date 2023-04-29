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
  DerivioPositionManager,
  IPositionRouter,
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";
import { swap } from "../src/swap";
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
  let positionRouter: IPositionRouter;
  let derivioPositionManager: DerivioPositionManager;
  let contracts: any;

  async function openDerivioA(tickLowerOffset: number, tickUpperOffset: number, shortLeverage: number) {
    const slot0 = await uniswapV3Pool.slot0();
    const tickSpacing = await uniswapV3Pool.tickSpacing();
  
    const lowerTick = slot0.tick - (slot0.tick % tickSpacing) + tickLowerOffset * tickSpacing;
    const upperTick = slot0.tick - (slot0.tick % tickSpacing) + tickUpperOffset * tickSpacing;
  
    await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
  
    await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
    await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
  
    await positionRouter.openDerivioA(
      {
        recipient: owner.address,
        tickLower: lowerTick,
        tickUpper: upperTick,
        feeTier: feeTier,
        amount0Desired: await weth.balanceOf(owner.address),
        amount1Desired: await usdc.balanceOf(owner.address),
        shortLeverage: shortLeverage,
        swapMaxSlippage: 0,
        shortMaxSlippage: 0,
      },
      weth.address,
      usdc.address,
    );
  }

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
    derivioPositionManager = contracts.derivioPositionManager;
  });

  describe("PositionRouter control flow", function () {

    it("#1 open DerivioAS by Position Router", async function () {

      await openDerivioA(-25, 10, 0);
      console.log(await derivioPositionManager.getAllPositions(owner.address));

      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      // console.log(174074702235888744 - 173193711205385178);
      // (await derivioPositionManager.getAllPositions(owner.address)).forEach((position, index) => {
      //   console.log(`Position #${index + 1}:`);
      //   console.log(`  Position Key: ${position.positionKey}`);
      //   position.protocolPosition.forEach((protocolPosition, protocolIndex) => {
      //     console.log(`  Protocol Position #${protocolIndex + 1}:`);
      //     console.log(`    Protocol Vault: ${protocolPosition.protocolManager}`);
      //     console.log(`    Position Info: ${protocolPosition.positionInfo}`);
      //   });
      // });
    });

    it("#2 open DerivioAL by Position Router", async function () {
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 25 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
      
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
      console.log(await derivioPositionManager.getAllPositions(owner.address));
      await positionRouter.getGmxPosition(weth.address, usdc.address);
    });

    it("#3 close DerivioAS by Position Router", async function () {
      
      await openDerivioA(-250, 100, 0);
  
      // Use getAllPositions to retrieve the positions
      const positions = await derivioPositionManager.getAllPositions(owner.address);
      const positionKeys = positions.map(pos => pos.positionKey);

      await positionRouter.closeDerivioA([positionKeys[0]], 'true', weth.address, usdc.address);
      
      // Get updated positions after closing
      const newPositions = await derivioPositionManager.getAllPositions(owner.address);
      const newPositionKeys = newPositions.map(pos => pos.positionKey);
  
      expect(newPositionKeys.length).to.equal(positionKeys.length - 1);

      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
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
        { value: ethers.utils.parseUnits("0.02", 18) }
      );

      
      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
      await positionRouter.getGmxPosition(weth.address, usdc.address);
      
      // Use getAllPositions to retrieve the positions
      const positions = await derivioPositionManager.getAllPositions(owner.address);
      const positionKeys = positions.map(pos => pos.positionKey);

      await positionRouter.closeDerivioA(
        [positionKeys[0]],
        'true',
        weth.address,
        usdc.address,
        { value: ethers.utils.parseUnits("0.0001", 18) }
      );

      // const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);

      // Get updated positions after closing
      const newPositions = await derivioPositionManager.getAllPositions(owner.address);
      const newPositionKeys = newPositions.map(pos => pos.positionKey);

      expect(newPositionKeys.length).to.equal(positionKeys.length - 1);
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      await positionRouter.getGmxPosition(weth.address, usdc.address);
    });

    it("#5 Open DerivioAS by Random initial amount0 & amount1", async function () {
      
      await openDerivioA(-25, 10, 0);
      console.log(await derivioPositionManager.getAllPositions(owner.address));
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    });

    it("#6 Open DerivioAS upper than current price", async function () {
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
      await openDerivioA(25, 40, 0);
      console.log(await derivioPositionManager.getAllPositions(owner.address));
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    });

    it("#7 Open DerivioAS lower than current price", async function () {
      
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
      await openDerivioA(-40, -25, 0);
      console.log(await derivioPositionManager.getAllPositions(owner.address));
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    });

    it("#8 Open DerivioAS at the same range multiple time", async function () {

      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
      await openDerivioA(-25, 10, 0);
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
      await openDerivioA(-25, 10, 0);
      console.log(await derivioPositionManager.getAllPositions(owner.address));
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    });

    it("#9 Position in Uniswap have fees", async function () {

      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
      await openDerivioA(-25, 10, 0);
      await openDerivioA(-25, 10, 0); // For swap and generating fees
      
      // await fundErc20(usdc, addresses.USDCWhale, owner.address, 100000, 6);
      // await swap(swapRouter, feeTier, owner, usdc, weth, 100000, 6);

      const positions = await derivioPositionManager.getAllPositions(owner.address);
      const positionKeys = positions.map(pos => pos.positionKey);

      const feesBefore = await derivioPositionManager.feeOf(positionKeys[0]);
      console.log("Fees before:", JSON.stringify(feesBefore, null, 2));
      console.log(feesBefore);
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));

      const wethBalanceBefore = await weth.balanceOf(owner.address);
      const usdcBalanceBefore = await usdc.balanceOf(owner.address);

      await derivioPositionManager.claimFees(owner.address, positionKeys[0]);

      const wethBalanceAfter = await weth.balanceOf(owner.address);
      const usdcBalanceAfter = await usdc.balanceOf(owner.address);
      console.log("weth: " + wethBalanceAfter + "  usdc: " + usdcBalanceAfter);
      
      const fee0 = feesBefore[0].fees[0].amount.toNumber();
      const fee1 = feesBefore[0].fees[1].amount.toNumber();

      expect(wethBalanceAfter.sub(wethBalanceBefore)).to.eq(fee0);
      expect(usdcBalanceAfter.sub(usdcBalanceBefore)).to.eq(fee1);
    });

  });

});
