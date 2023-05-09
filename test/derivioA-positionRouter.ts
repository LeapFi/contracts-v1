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
import { getPriceBits } from "../src/utilities";
import { BigNumber, BytesLike, ContractReceipt } from "ethers";
import { inspect } from 'util';

type Position = ReturnType<DerivioPositionManager["getAllPositions"]> extends Promise<Array<infer T>> ? T : never;
// type AggregateInfo = Position["aggregateInfos"][number];

type Fund = ReturnType<GmxManager["feesOf"]> extends Promise<Array<infer T>> ? T : never;
type CloaseArgs = Parameters<IPositionRouter["closeDerivioA"]>[0] extends Array<infer T> ? T : never;
type ProtocolOpenResult = Position["aggregateInfos"][number]["openResult"];
type ProtocolCloseResult = ReturnType<IPositionRouter["closeDerivioA"]> extends Promise<Array<Array<infer T>>> ? T : never;

type OpenArgs = Parameters<IPositionRouter["openDerivioFuturePositions"]>[0] extends Array<infer T> ? T : never;
type ProtocolOpenResults = ReturnType<IPositionRouter["openDerivioFuturePositions"]> extends Promise<Array<Array<infer T>>> ? T : never;


// type Fund = ReturnType<GmxManager["feesOf"]> extends Promise<Array<infer T>> ? T : never; 

interface PositionParse {
  positionKey: string;
  aggregateInfos: BaseAggregateInfo[];
}

// interface ProtocolOpenResult {
//   manager: string;
//   key: string;
//   infos: string;
// }

// interface Fund {
//   token: string;
//   amount: BigInt;
// }

interface BaseAggregateInfo {
  manager: String;
  key: String;
  openInfos: OpenInfo;
}

interface GmxManagerAggregateInfo extends BaseAggregateInfo {
  currentInfos: GmxManagerInfo;
}

interface UniV3ManagerAggregateInfo extends BaseAggregateInfo {
  fees: Fund[];
}

interface OpenInfo {}

interface UniV3OpenInfo extends OpenInfo {
  liquidity: String;
  token0: String;
  token1: String;
  feeTier: String;
}

interface GmxOpenInfo extends OpenInfo {
  collateralToken: String;
  indexToken: String;
  isLong: boolean;
  collateralAmount: String;
  sizeDelta: String;
}

interface GmxManagerInfo {
  isLong: boolean;
  sizeDelta: String;
  collateral: String;
  averagePrice: String;
  entryFundingRate: String;
  reserveAmount: String;
  realisedPnl: String;
  realisedPnLPositive: boolean;
  lastIncreasedTime: String;
}

interface UniV3ManagerInfo {
  // ... define the structure based on the returned data from UniV3Manager's infoOf
}

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

  async function openDerivioA(tickLowerOffset: number, tickUpperOffset: number, shortLeverage: number, value: number) {
    const slot0 = await uniswapV3Pool.slot0();
    const tickSpacing = await uniswapV3Pool.tickSpacing();
  
    const lowerTick = slot0.tick - (slot0.tick % tickSpacing) + tickLowerOffset * tickSpacing;
    const upperTick = slot0.tick - (slot0.tick % tickSpacing) + tickUpperOffset * tickSpacing;
  
    await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
  
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
        amount0Desired: await weth.balanceOf(owner.address),
        amount1Desired: await usdc.balanceOf(owner.address),
        shortLeverage: shortLeverage,
        swapSqrtPriceLimitX96: 0,
        shortMaxSlippage: 0,
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
  }
  
  async function closeDerivioAPositions(positionKeys: BytesLike[], swapToCollateral: boolean, token0Address: string, token1Address: string, value: number) {
    const valueInput = ethers.utils.parseUnits(value.toString(), 18);
    const closeArgsList : CloaseArgs[] = positionKeys.map(positionKey => ({
      value: valueInput, // Replace this with the desired value for each position
      positionKey: positionKey,
      swapToCollateral: swapToCollateral
    }));

    return await positionRouter.closeDerivioA(closeArgsList, token0Address, token1Address, { value: valueInput });
  }

  async function getPositionsInfos(derivioPositionManager: any, accAddr: string): Promise<PositionParse[]> {

    const positions: Position[]  = await derivioPositionManager.getAllPositions(accAddr);
    console.log(positions);

    const posList: PositionParse[] = [];
    positions.forEach((position) => {

      const pos: PositionParse = {
        positionKey: position.positionKey,
        aggregateInfos: [],
      }
      
      // Iterate through the aggregateInfos within each position
      position.aggregateInfos.forEach((aggregateInfo) => {
        // Check the contract address and parse the feesOf and infoOf accordingly
        if (aggregateInfo.openResult.manager === contracts.gmxManager.address) {

          const decodedOpenValues = ethers.utils.defaultAbiCoder.decode(
            [
              'address', // _collateralToken
              'address', // _indexToken
              'bool',    // _isLong
              'uint256', // _collateralAmount
              'uint256'  // _shortDelta
            ],
            aggregateInfo.openResult.infos
          );
          const gmxOpenInfo: GmxOpenInfo = {
            collateralToken: decodedOpenValues[0],
            indexToken: decodedOpenValues[1],
            isLong: decodedOpenValues[2],
            collateralAmount: decodedOpenValues[3].toString(),
            sizeDelta: decodedOpenValues[4].toString()
          };

          const decodedValues = ethers.utils.defaultAbiCoder.decode(
            [
              'bool', 'uint256', 'uint256', 'uint256', 'uint256',
              'uint256', 'uint256', 'bool', 'uint256'
            ],
            aggregateInfo.currentInfos
          );
          const gmxManagerInfo: GmxManagerInfo = {
            isLong: decodedValues[0],
            sizeDelta: decodedValues[1].toString(),
            collateral: decodedValues[2].toString(),
            averagePrice: decodedValues[3].toString(),
            entryFundingRate: decodedValues[4].toString(),
            reserveAmount: decodedValues[5].toString(),
            realisedPnl: decodedValues[6].toString(),
            realisedPnLPositive: decodedValues[7],
            lastIncreasedTime: decodedValues[8].toString()
          };

          const gmxManagerAggregateInfo: GmxManagerAggregateInfo = {
            manager: "Gmx Manager",
            key: aggregateInfo.openResult.key,
            openInfos: gmxOpenInfo,
            currentInfos: gmxManagerInfo,
          };

          pos.aggregateInfos.push(gmxManagerAggregateInfo);
          
        } else if (aggregateInfo.openResult.manager === contracts.uniV3Manager.address) {

          const decodedOpenValues = ethers.utils.defaultAbiCoder.decode(
            [
              'uint256', // liquidity
              'address', // token0
              'address', // token1
              'uint256', // feeTier
            ],
            aggregateInfo.openResult.infos
          );
          const uniV3OpenInfo: UniV3OpenInfo = {
            liquidity: decodedOpenValues[0].toString(),
            token0: decodedOpenValues[1],
            token1: decodedOpenValues[2],
            feeTier: decodedOpenValues[3].toString(),
          };

          const fees = aggregateInfo.fees.map((fee) => {
            return {
              token: fee[0].toString(),
              amount: fee[1].toString(),
            };
          });

          const uniV3ManagerAggregateInfo = {
            manager: "Uniswap V3 Manager",
            key: aggregateInfo.openResult.key,
            openInfos: uniV3OpenInfo,
            fees: fees,
          };

          pos.aggregateInfos.push(uniV3ManagerAggregateInfo);
        }
      });

      posList.push(pos);
    });

    return posList;
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

    // it("#1 open DerivioAS by Position Router", async function () {

    //   await openDerivioA(-25, 10, 0, 0);
      
    //   console.log(await derivioPositionManager.getAllPositions(owner.address));
    // });

    // it("#2 open DerivioAL by Position Router", async function () {
      
    //   await openDerivioA(-25, 10, 1000000, 0.02);
      
    //   console.log('positionsInfos:', await getPositionsInfos(derivioPositionManager, owner.address));
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

    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   await openDerivioA(-25, 10, 0, 0);
    //   await openDerivioA(-25, 10, 0, 0); // For swap and generating fees
      
    //   // await fundErc20(usdc, addresses.USDCWhale, owner.address, 100000, 6);
    //   // await swap(swapRouter, feeTier, owner, usdc, weth, 100000, 6);

    //   const positions = await derivioPositionManager.getAllPositions(owner.address);
    //   const positionKeys = positions.map(pos => pos.positionKey);

    //   const feesBefore = await derivioPositionManager.feeOf(positionKeys[0]);
    //   console.log("Fees before:", JSON.stringify(feesBefore, null, 2));
    //   console.log(feesBefore);
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));

    //   const wethBalanceBefore = await weth.balanceOf(owner.address);
    //   const usdcBalanceBefore = await usdc.balanceOf(owner.address);

    //   await derivioPositionManager.claimFees(owner.address, positionKeys[0]);

    //   const wethBalanceAfter = await weth.balanceOf(owner.address);
    //   const usdcBalanceAfter = await usdc.balanceOf(owner.address);
    //   console.log("weth: " + wethBalanceAfter + "  usdc: " + usdcBalanceAfter);
      
    //   const fee0 = feesBefore[0].fees[0].amount.toNumber();
    //   const fee1 = feesBefore[0].fees[1].amount.toNumber();

    //   expect(wethBalanceAfter.sub(wethBalanceBefore)).to.eq(fee0);
    //   expect(usdcBalanceAfter.sub(usdcBalanceBefore)).to.eq(fee1);
    // });

    // it("#10 Open DerivioFuture", async function () {
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
    //   let value = ethers.utils.parseUnits("0.0001", 18);

    //   await fundErc20(usdc, addresses.USDCWhale, owner.address, 50, 6);
    //   await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      
    //   const collateralAmount = await usdc.balanceOf(owner.address);
    //   const sizeDelta = collateralAmount.mul(500).div(100);

    //   // Long
    //   await positionRouter.openDerivioFuturePositions([
    //     {
    //       recipient: owner.address,
    //       value: value,
    //       isLong: true,
    //       collateralAmount: collateralAmount,
    //       sizeDelta: sizeDelta,
    //       acceptPrice: ethers.constants.MaxUint256,
    //     }],
    //     usdc.address,
    //     weth.address,
    //     { value: value }
    //   );

    //   // Short
    //   // await positionRouter.openDerivioFuturePositions([
    //   //   {
    //   //     recipient: owner.address,
    //   //     value: value,
    //   //     isLong: false,
    //   //     collateralAmount: collateralAmount,
    //   //     sizeDelta: sizeDelta,
    //   //     acceptPrice: 0,
    //   //   }],
    //   //   usdc.address,
    //   //   weth.address,
    //   //   { value: value }
    //   // );

    //   // console.log('setPricesWithBitsAndExecute.........................');
    //   const gmxKeeper = await ethers.getImpersonatedSigner(addresses.GMXKeeper);
    //   // await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits(getPriceBits([]), await getBlockTime());
    //   // await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBitsAndExecute(
    //   //   "443915394701494028093366599013166",
    //   //   await getBlockTime(), 
    //   //   9999999999, // _endIndexForIncreasePositions
    //   //   9999999999, // _endIndexForDecreasePositions
    //   //   1000, // _maxIncreasePositions
    //   //   1000 // _maxDecreasePositions
    //   // );

    //   // await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits("443915394701494028093366599013166", await getBlockTime());

    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
    //   const tx = await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   await gmxFastPriceFeed.connect(gmxKeeper).setPricesWithBits("443915394701494028093366599013166", await getBlockTime());

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


    //   const positions = await derivioPositionManager.getAllPositions(owner.address);
    //   const positionKeys = positions.map(pos => pos.positionKey);
    //   console.log(positions);
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
          shortMaxSlippage: 0,
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
          shortMaxSlippage: 0,
        }],
        weth.address,
        usdc.address,
        { value: ethers.utils.parseUnits("0.0001", 18) }
      );

      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);
      
      console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
    });

    it("#13 Slippage control of the swap", async function () {
      
    });


  }); 

});
