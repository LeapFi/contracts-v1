import { expect } from "chai";
import { ethers } from "hardhat";
import hre = require("hardhat");
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxPositionManager,
  IGmxVault,
  IGmxPriceFeed,
  IGmxFastPriceFeed,
  DerivioA,
  DerivioPositionManager,
  IPositionRouter,
  IProtocolPositionManager,
  GmxManager,
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";
import { swap } from "../src/swap";
import { setupContracts } from "../src/setupContracts";
import { fundErc20 } from "../src/fundErc20";
import { setPricesWithBitsAndExecute, getBlockTime } from "../src/executeGmxPosition";
import { getPriceBits } from "../src/utilities";
import { getPositionsInfos } from "../src/position";
import { inspect } from 'util';
import { BigintIsh, Currency, CurrencyAmount, Fraction, Price, Token } from '@uniswap/sdk-core';

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
  let gmxPositionManager: IGmxPositionManager;
  let gmxFastPriceFeed: IGmxFastPriceFeed;
  let gmxEthPriceFeed: IGmxPriceFeed;
  let gmxVault: IGmxVault;
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
      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GmxFastPriceFeed);
      const tx = await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GmxFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GmxFastPriceFeed);

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

    const positionKeeper = await ethers.getImpersonatedSigner(addresses.GmxFastPriceFeed);
    await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GmxFastPriceFeed);
  };
  

  // Reuse the same setup in every test.
  beforeEach("Setting contracts", async function () {

    // Contracts are deployed using the first signer/account by default
    [owner, otherAccount] = await ethers.getSigners(); 
    contracts = await setupContracts(feeTier);
    uniswapV3Pool = contracts.uniswapV3Pool;
    swapRouter = contracts.swapRouter;
    gmxPositionRouter = contracts.gmxPositionRouter;
    gmxPositionManager = contracts.gmxPositionManager;
    gmxVault = contracts.gmxVault;
    gmxFastPriceFeed = contracts.gmxFastPriceFeed;
    gmxEthPriceFeed = contracts.gmxEthPriceFeed;
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
      
    //   await openDerivioA(slot0, -50, 50, 0, 0);
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

    // it("#12 Open DerivioA", async function () {
      
    //   const slot0 = await uniswapV3Pool.slot0();
    //   const tickSpacing = await uniswapV3Pool.tickSpacing();
    
    //   const lowerTick = slot0.tick - (slot0.tick % tickSpacing) -25 * tickSpacing;
    //   const upperTick = slot0.tick - (slot0.tick % tickSpacing) +10 * tickSpacing;
    
    //   await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
    
    //   await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
    //   await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      
    //   await positionRouter.openDerivioAPositions([
    //     {
    //       recipient: owner.address,
    //       value: 0,
    //       tickLower: lowerTick,
    //       tickUpper: upperTick,
    //       feeTier: feeTier,
    //       amount0Desired: 0,
    //       amount1Desired: ethers.utils.parseUnits("500", 6),
    //       shortLeverage: 0,
    //       swapSqrtPriceLimitX96: 0,
    //       shortPriceLimit: 0,
    //     },
    //     {
    //       recipient: owner.address,
    //       value: ethers.utils.parseUnits("0.0001", 18),
    //       tickLower: lowerTick,
    //       tickUpper: upperTick,
    //       feeTier: feeTier,
    //       amount0Desired: 0,
    //       amount1Desired: ethers.utils.parseUnits("500", 6),
    //       shortLeverage: 1e6,
    //       swapSqrtPriceLimitX96: 0,
    //       shortPriceLimit: 0,
    //     }],
    //     weth.address,
    //     usdc.address,
    //     { value: ethers.utils.parseUnits("0.0001", 18) }
    //   );

    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
    //   await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
      
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    // });

    // it("#13 Slippage control of the swap", async function () {
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      
    //   // Long
    //   await openDerivioFuture(true, 500, 5);
    //   await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    // });

    it("#14 Simulate GMX liquidation", async function () {
      
      const isLong = false;

      //  Short
      await openDerivioFuture(isLong, 500, 10);
      let positions = await getPositionsInfos(derivioPositionManager, owner.address);

      let minVaultAddress: string = '';
      positions.forEach(position => {
        position.aggregateInfos.forEach(info => {
          minVaultAddress = '0x' + info.key.slice(-40);
          // info.key = address;
        });
      });
      console.log('address:', minVaultAddress);
      console.log('positionsInfos:', JSON.stringify(positions, null, 2));
      
      const btcAddress = '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f';
      const linkAddress = '0xf97f4df75117a78c1A5a0DBb814Af92458539FB4';
      const uniAddress = '0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0';
      
      console.log('weth min price:', await gmxVault.getMinPrice(weth.address));
      console.log('weth max price:', await gmxVault.getMaxPrice(weth.address));


      const btcPrice = '21633000';
      const ethPrice =  '4000000';
      const linkPrice =    '6000';
      const uniPrice =     '6000';
      const priceBits = await getPriceBits([btcPrice, ethPrice, linkPrice, uniPrice]);

      const gmxKeeper = await ethers.getImpersonatedSigner(addresses.GmxKeeper);
      await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits(priceBits, await getBlockTime());

      await fundErc20(usdc, addresses.USDCWhale, owner.address, 5000000, 6);
      await swap(swapRouter, feeTier, owner, usdc, weth, 5000000, 6);

      console.log('weth min price:', await gmxVault.getMinPrice(weth.address));
      console.log('weth max price:', await gmxVault.getMaxPrice(weth.address));
      
      // liquidate short position
      // const [liquidationState, marginFee] = await gmxVault.validateLiquidation(owner.address, usdc.address, weth.address, isLong, false);
      // console.log('liquidationState:', liquidationState);
      // console.log('marginFee:', marginFee);

      const liquidator = await ethers.getImpersonatedSigner(addresses.GmxLiquidator);
      await gmxPositionManager.connect(liquidator).liquidatePosition(minVaultAddress, usdc.address, weth.address, false, liquidator.address);
      console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    });

    it("#15 Simulate GMX price feed", async function () {
      
      const isLong = false;

      //  Short
      await openDerivioFuture(isLong, 500, 10);
      let positions = await getPositionsInfos(derivioPositionManager, owner.address);

      let minVaultAddress: string = '';
      positions.forEach(position => {
        position.aggregateInfos.forEach(info => {
          minVaultAddress = '0x' + info.key.slice(-40);
          // info.key = address;
        });
      });
      console.log('address:', minVaultAddress);
      console.log('positionsInfos:', JSON.stringify(positions, null, 2));
      
      
      const btcAddress = '0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f';
      const linkAddress = '0xf97f4df75117a78c1A5a0DBb814Af92458539FB4';
      const uniAddress = '0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0';
      
      // console.log('btc min price:', await gmxVault.getMinPrice(btcAddress));
      // console.log('btc max price:', await gmxVault.getMaxPrice(btcAddress));

      console.log('weth min price:', await gmxVault.getMinPrice(weth.address));
      console.log('weth max price:', await gmxVault.getMaxPrice(weth.address));
      
      // console.log('link min price:', await gmxVault.getMinPrice(linkAddress));
      // console.log('link max price:', await gmxVault.getMaxPrice(linkAddress));

      // console.log('uni min price:', await gmxVault.getMinPrice(uniAddress));
      // console.log('uni max price:', await gmxVault.getMaxPrice(uniAddress));

      const btcPrice = '21633000';
      const ethPrice =  '1879000';
      const linkPrice =    '6000';
      const uniPrice =     '6000';

      // const priceKeeper = await ethers.getImpersonatedSigner('0x2F3b388EB017613eb51F06843DFEF12Db1fDD3c5');
      // await gmxEthPriceFeed.connect(priceKeeper).setLatestAnswer('1230000000');

      const _report = '0x0000000000000000000000f6d9397093865a569a3b827fbe021b4e00040a6f0406040500070308010902000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000002bc0f7642f0000000000000000000000000000000000000000000000000000002bc160c68c0000000000000000000000000000000000000000000000000000002bc160c68c0000000000000000000000000000000000000000000000000000002bc1e1e2800000000000000000000000000000000000000000000000000000002bc4b834000000000000000000000000000000000000000000000000000000002bc4e373cf0000000000000000000000000000000000000000000000000000002bc4e373cf0000000000000000000000000000000000000000000000000000002bc5f422e80000000000000000000000000000000000000000000000000000002bc5f8a3400000000000000000000000000000000000000000000000000000002bc8a74880';
      const _rs = ['0x0aacb759a4493118cfbe6113d3b4dcb726b693c351ec71f0e5c671846b2843d9', '0x6cd68bce9205af75168312fc8552e8142446719a0cf4255b8e9e77b725ad17dc', '0xef22f212d8763e67a2d71e4be44e69f339f21f12fbd63fee6749db2c37723e41', '0xdb3896dd816325f7cbffb8340bfd79912e3352df407409463bd9ae09f97b0042'];
      const _ss = ['0x15f7e25385402952c547934c1ecc4385e5d3bab00ae40322829b8fa7ceb09d96', '0x59264fc30b8453cb7738de0ae82ba412add0f7ff2e66f1bd31c79f219e054d66', '0x69c55429a5188f3fca9c06bd80a36c28437b8e69363ed89d3d58c61ba838b852', '0x196dbd9386fd8b9d1fdbb054d9e6defd8d89e708b808ba864364010890b25e6f'];
      const _rawVs = '0x0001010000000000000000000000000000000000000000000000000000000000';

      const chainLinkKeeper = await ethers.getImpersonatedSigner('0xa82d4edb72dd3d167d00058f2404658f4e9a010a');
      await gmxEthPriceFeed.connect(chainLinkKeeper).transmit(_report, _rs, _ss, _rawVs, { gasLimit: 5000000 });


      const priceBits = await getPriceBits([btcPrice, ethPrice, linkPrice, uniPrice]);

      const gmxKeeper = await ethers.getImpersonatedSigner(addresses.GmxKeeper);
      await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits(priceBits, await getBlockTime());

      await fundErc20(usdc, addresses.USDCWhale, owner.address, 5000000, 6);
      await swap(swapRouter, feeTier, owner, usdc, weth, 5000000, 6);

      // console.log('btc min price:', await gmxVault.getMinPrice(btcAddress));
      // console.log('btc max price:', await gmxVault.getMaxPrice(btcAddress));

      console.log('weth min price:', await gmxVault.getMinPrice(weth.address));
      console.log('weth max price:', await gmxVault.getMaxPrice(weth.address));
      
      // console.log('link min price:', await gmxVault.getMinPrice(linkAddress));
      // console.log('link max price:', await gmxVault.getMaxPrice(linkAddress));

      // console.log('uni min price:', await gmxVault.getMinPrice(uniAddress));
      // console.log('uni max price:', await gmxVault.getMaxPrice(uniAddress));

      await openDerivioFuture(isLong, 500, 10);
      positions = await getPositionsInfos(derivioPositionManager, owner.address);
      console.log('positionsInfos:', JSON.stringify(positions, null, 2));
    });


  }); 

});
