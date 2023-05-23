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
  IProtocolPositionManager,
  GmxManager
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";
import { swap } from "../src/swap";
import { setupContracts } from "../src/setupContracts";
import { fundErc20 } from "../src/fundErc20";
import { setPricesWithBitsAndExecute, getBlockTime } from "../src/executeGmxPosition";
import { getPositionsInfos } from "../src/position";
import { getPriceBits, ethUsdcPriceToSqrtPriceX96, ethUsdcPriceToSqrtPriceX962 } from "../src/utilities";
import { BigNumber, BytesLike, ContractReceipt } from "ethers";
import { inspect } from 'util';
import { BigintIsh, Currency, CurrencyAmount, Fraction, Price, Token } from '@uniswap/sdk-core';
import { FeeAmount, priceToClosestTick, TickMath } from '@uniswap/v3-sdk';
import JSBI from 'jsbi';

// type AggregateInfo = Position["aggregateInfos"][number];
// type Fund = ReturnType<GmxManager["feesOf"]> extends Promise<Array<infer T>> ? T : never;


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

  async function openDerivioA(slot0: any, tickLowerOffset: number, tickUpperOffset: number, shortLeverage: number, value: number) {
    // const slot0 = await uniswapV3Pool.slot0();
    const tickSpacing = await uniswapV3Pool.tickSpacing();
  
    const lowerTick = slot0.tick - (slot0.tick % tickSpacing) + tickLowerOffset * tickSpacing;
    const upperTick = slot0.tick - (slot0.tick % tickSpacing) + tickUpperOffset * tickSpacing;

    console.log('lowerTick:', lowerTick);
    console.log('upperTick:', upperTick);
    
    const token1Amount = 1000;
    await fundErc20(usdc, addresses.USDCWhale, owner.address, token1Amount, 6);
  
    await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
    await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
    
    const valueInput = ethers.utils.parseUnits(value.toString(), 18);

    const ETH = new Token(1, weth.address, 18, 'WETH', 'Ether');
    const USDC = new Token(1, usdc.address, 6, 'USDC', 'USD Coin');

    const ethAmount = ethers.utils.parseUnits('1', ETH.decimals);
    const usdcAmount = ethers.utils.parseUnits('1851', USDC.decimals);

    const ethAmountJSBI = JSBI.BigInt(ethAmount.toString());
    const usdcAmountJSBI = JSBI.BigInt(usdcAmount.toString());

    const ethAmountCurrency = CurrencyAmount.fromRawAmount(ETH, ethAmountJSBI.toString());
    const usdcAmountCurrency = CurrencyAmount.fromRawAmount(USDC, usdcAmountJSBI.toString());

    const ethUsdcPrice = new Price(ETH, USDC, ethAmountCurrency.quotient, usdcAmountCurrency.quotient);
    const sqrtPriceX96 = ethUsdcPriceToSqrtPriceX962(ethUsdcPrice);
    console.log("ts sqrtPriceX96:", sqrtPriceX96);

    await positionRouter.openDerivioAPositions([
      {
        recipient: owner.address,
        value: valueInput,
        tickLower: lowerTick,
        tickUpper: upperTick,
        feeTier: feeTier,
        amount0Desired: 0,
        amount1Desired: ethers.utils.parseUnits(token1Amount.toString(), 6),
        shortLeverage: shortLeverage,
        swapSqrtPriceLimitX96: 0,
        shortPriceLimit: 0,
      }],
      weth.address,
      usdc.address,
      { value: valueInput }
    );

    if (shortLeverage != 0) {
      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      const tx = await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);

      // Print out all events in the transaction
      // const receipt = await tx.wait();
      // for (const event of receipt.events || []) {
      //   try {
      //     const parsedEvent = gmxFastPriceFeed.interface.parseLog(event);
      //     console.log();
      //     console.log();
      //     console.log(`Log index: ${event.logIndex}`, `Event name: ${parsedEvent.name}`);
          
      //     const replacer = (key, value) => {
      //       if (value && value.type === 'BigNumber' && value.hex) {
      //         return value.toBigInt().toString(); // Convert BigNumber hex to string
      //       }
      //       return value;
      //     };
      
      //     console.log(`Event args: ${JSON.stringify(parsedEvent.args, replacer, 2)}`);
      //     console.log("----");
      //   } 
      //   catch (error) {
      //     console.log("Unrecognized event:", inspect(event, { depth: null, colors: true }));
      //   };
      // }
    }
  };
  
  async function openDerivioFuture(isLong: boolean, collateralAmount: number, leverage: number) {
    
    let value = ethers.utils.parseUnits("0.001", 18);

    await fundErc20(usdc, addresses.USDCWhale, owner.address, collateralAmount, 6);
    await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
    
    const collateralAmountIn = ethers.utils.parseUnits(collateralAmount.toString(), 6);
    const sizeDelta = ethers.utils.parseUnits((collateralAmount * leverage).toString(), 6);

    await positionRouter.openDerivioFuturePositions([
        {
          recipient: owner.address,
          value: value,
          isLong: isLong,
          collateralAmount: collateralAmountIn,
          sizeDelta: sizeDelta,
          acceptPrice: "1384830000000000000000000000000000" // isLong ? ethers.constants.MaxUint256 : 0,
        }],
        usdc.address,
        weth.address,
        { value: value }
      );
  };
  

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

    // it("#1 open DerivioAS by Position Router", async function () {

    //   const slot0 = await uniswapV3Pool.slot0();
    //   await openDerivioA(slot0, -25, 10, 0, 0);
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    // });

    // it("#2 open DerivioAL by Position Router", async function () {
      
    //   const slot0 = await uniswapV3Pool.slot0();
    //   await openDerivioA(slot0, -25, 10, 1000000, 0.0001);
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    // });

    // it("#3 close DerivioAS by Position Router", async function () {
      
    //   await openDerivioA(-250, 100, 0, 0);
  
    //   // Use getAllPositions to retrieve the positions
    //   const positions = await derivioPositionManager.getAllPositions(owner.address);
    //   const positionKeys = positions.map(pos => pos.positionKey);

    //   await closeDerivioAPositions([positionKeys[0]], true, weth.address, usdc.address, 0);
    //   // await positionRouter.closeDerivioA([positionKeys[0]], 'true', weth.address, usdc.address);
      
    //   // Get updated positions after closing
    //   const newPositions = await derivioPositionManager.getAllPositions(owner.address);
    //   const newPositionKeys = newPositions.map(pos => pos.positionKey);
  
    //   expect(newPositionKeys.length).to.equal(positionKeys.length - 1);

    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    // });

    // it("#4 close DerivioAL by Position Router", async function () {
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))

    //   await openDerivioA(-25, 10, 500000, 0.02);
    //   console.log('positionsInfos:', await getPositionsInfos(derivioPositionManager, owner.address));
      
    //   // Use getAllPositions to retrieve the positions
    //   const positions = await derivioPositionManager.getAllPositions(owner.address);
    //   const positionKeys = positions.map(pos => pos.positionKey);

    //   await closeDerivioAPositions([positionKeys[0]], true, weth.address, usdc.address, 0.0001);

    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
    //   await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);

    //   // Get updated positions after closing
    //   const newPositions = await derivioPositionManager.getAllPositions(owner.address);
    //   const newPositionKeys = newPositions.map(pos => pos.positionKey);

    //   expect(newPositionKeys.length).to.equal(positionKeys.length - 1);
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    //   console.log('positionsInfos:', await getPositionsInfos(derivioPositionManager, owner.address));
    // });

    // it("#5 Open DerivioAS by Random initial amount0 & amount1", async function () {
      
    //   await openDerivioA(-25, 10, 0, 0);
    //   console.log(await derivioPositionManager.getAllPositions(owner.address));
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    // });

    // it("#6 Open DerivioAS upper than current price", async function () {
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   await openDerivioA(25, 40, 0, 0);
    //   console.log(await derivioPositionManager.getAllPositions(owner.address));
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    // });

    // it("#7 Open DerivioAS lower than current price", async function () {
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   await openDerivioA(-40, -25, 0, 0);
    //   console.log(await derivioPositionManager.getAllPositions(owner.address));
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    // });

    // it("#8 Open DerivioAS at the same range multiple time", async function () {

    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   await openDerivioA(-25, 10, 0, 0);
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   await openDerivioA(-25, 10, 0, 0);
    //   console.log(await derivioPositionManager.getAllPositions(owner.address));
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    // });

    // it("#9 Position in Uniswap have fees", async function () {

    //   const slot0 = await uniswapV3Pool.slot0();
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   await openDerivioA(slot0, -25, 30, 0, 0);
    //   // await openDerivioA(slot0, -25, 10, 0, 0);

    //   await fundErc20(usdc, addresses.USDCWhale, owner.address, 100000, 6);
    //   await swap(swapRouter, feeTier, owner, usdc, weth, 100000, 6);
    //   // console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
      
    //   const positions = await derivioPositionManager.getAllPositions(owner.address);
    //   const positionKeys = positions.map(pos => pos.positionKey);

    //   const feesBefore = await derivioPositionManager.feeOf(positionKeys[0]);
    //   console.log("Fees before:", JSON.stringify(feesBefore, null, 2));
    //   console.log(feesBefore);
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));

    //   const wethBalanceBefore = await weth.balanceOf(owner.address);
    //   const usdcBalanceBefore = await usdc.balanceOf(owner.address);

    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    //   await derivioPositionManager.claimFees(owner.address, positionKeys[0]);

    //   const wethBalanceAfter = await weth.balanceOf(owner.address);
    //   const usdcBalanceAfter = await usdc.balanceOf(owner.address);
    //   console.log("weth: " + wethBalanceAfter + "  usdc: " + usdcBalanceAfter);
      
    //   const fee0 = feesBefore[0].fees[0].amount.toNumber();
    //   const fee1 = feesBefore[0].fees[1].amount.toNumber();

    //   expect(wethBalanceAfter.sub(wethBalanceBefore)).to.eq(fee0);
    //   expect(usdcBalanceAfter.sub(usdcBalanceBefore)).to.eq(fee1);
    // });

    // it("#9.1 Out of range swap event don't have fees", async function () {

    //   const slot0 = await uniswapV3Pool.slot0();
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   await openDerivioA(slot0, -1, 1, 0, 0);

    //   await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000000, 6);
    //   await swap(swapRouter, feeTier, owner, usdc, weth, 1000000, 6);
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
      
    //   await openDerivioA(slot0, -1, 1, 0, 0); // For swap and generating fees
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));

    //   await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
    //   await swap(swapRouter, feeTier, owner, usdc, weth, 1000, 6);
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    // });

    // it("#10 Open DerivioFuture", async function () {
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    //   const gmxKeeper = await ethers.getImpersonatedSigner(addresses.GMXKeeper);
    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      
    //   // Long
    //   await openDerivioFuture(true, 500, 5);
      
    //   // Short
    //   // await openDerivioFuture(false, 500, 5);

    //   // console.log('setPricesWithBitsAndExecute.........................');
    //   // await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits(getPriceBits([]), await getBlockTime());
    //   // const tx = await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBitsAndExecute(
    //   //   "399072254701357173801603550548272",
    //   //   "1683857962", 
    //   //   9999999999, // _endIndexForIncreasePositions
    //   //   9999999999, // _endIndexForDecreasePositions
    //   //   10000, // _maxIncreasePositions
    //   //   10000 // _maxDecreasePositions
    //   // );

    //   // await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBitsAndExecute(
    //   //   "399151482863852991389922179535799",
    //   //   "1683858077", 
    //   //   9999999999, // _endIndexForIncreasePositions
    //   //   9999999999, // _endIndexForDecreasePositions
    //   //   0, // _maxIncreasePositions
    //   //   1000 // _maxDecreasePositions
    //   // );

    //   // await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits("443915394701494028093366599013166", await getBlockTime());

    //   const tx = await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   // await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   // await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits("443915394701494028093366599013166", await getBlockTime());

    //   const receipt = await tx.wait();
    //   for (const event of receipt.events || []) {
    //     try {
    //       const parsedEvent = gmxFastPriceFeed.interface.parseLog(event);
    //       console.log();
    //       console.log();
    //       console.log(`Log index: ${event.logIndex}`, `Event name: ${parsedEvent.name}`);

    //       // Loop through the parsedEvent.args array and parse all parameters
    //       const eventParams = Object.entries(parsedEvent.args).slice(1); // Skip the first element (event signature)
    //       for (const [key, value] of eventParams) {
    //         if (isNaN(key)) { // Check if the key is a string (not a number)
    //           console.log(`${key}:`, value);
    //         }
    //       }

    //       console.log("----");
    //     } catch (error) {
    //       console.log("Unrecognized event:", inspect(event, { depth: null, colors: true }));
    //     }
    //   }


    //   // const positionKeys = positions.map(pos => pos.positionKey);
    //   // console.log(positions);
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    //   // console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   // value = ethers.utils.parseUnits("0.0001", 18);
    //   // await positionRouter.closeDerivioFuture([
    //   //   {
    //   //     value: value,
    //   //     positionKey: positionKeys[0],
    //   //     minOut: 0,
    //   //     acceptPrice: 0
    //   //   }],
    //   //   usdc.address,
    //   //   weth.address,
    //   //   { value: value }
    //   // );

    //   // await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   // await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);
      
    //   // const newPositions = await derivioPositionManager.getAllPositions(owner.address);
    //   // const newPositionKeys = newPositions.map(pos => pos.positionKey);
  
    //   // expect(newPositionKeys.length).to.equal(positionKeys.length - 1);
    //   // console.log(newPositionKeys);
    // });

    // it("#11 Should be open DerivioAL by with leverage", async function () {
      
    //   await openDerivioA(-25, 10, 2000000, 0.0001);
    //   console.log('positionsInfos:', await getPositionsInfos(derivioPositionManager, owner.address));
    // });

    it("#12 Open DerivioA", async function () {
      
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();
    
      const lowerTick = slot0.tick - (slot0.tick % tickSpacing) -25 * tickSpacing;
      const upperTick = slot0.tick - (slot0.tick % tickSpacing) +10 * tickSpacing;
    
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
    
      await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
      await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      
      await positionRouter.openDerivioAPositions([
        {
          recipient: owner.address,
          value: 0,
          tickLower: lowerTick,
          tickUpper: upperTick,
          feeTier: feeTier,
          amount0Desired: 0,
          amount1Desired: ethers.utils.parseUnits("500", 6),
          shortLeverage: 0,
          swapSqrtPriceLimitX96: 0,
          shortPriceLimit: 0,
        },
        {
          recipient: owner.address,
          value: ethers.utils.parseUnits("0.0001", 18),
          tickLower: lowerTick,
          tickUpper: upperTick,
          feeTier: feeTier,
          amount0Desired: 0,
          amount1Desired: ethers.utils.parseUnits("500", 6),
          shortLeverage: 1e6,
          swapSqrtPriceLimitX96: 0,
          shortPriceLimit: 0,
        }],
        weth.address,
        usdc.address,
        { value: ethers.utils.parseUnits("0.0001", 18) }
      );

      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
      
      console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    });

    // it("#13 Slippage control of the swap", async function () {
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      
    //   // Long
    //   await openDerivioFuture(true, 500, 5);
    //   await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    // });


  }); 

});
