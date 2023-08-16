import { ethers } from "hardhat";
import { BytesLike, BigNumber } from "ethers";
import {
    IPositionRouter,
    DerivioPositionManager,
  } from "../typechain";
import BN from 'bn.js'

type Position = ReturnType<DerivioPositionManager["getAllPositions"]> extends Promise<Array<infer T>> ? T : never;

interface PositionParse {
    positionKey: string;
    timestamp: String;
    aggregateInfos: Array<GmxManagerAggregateInfo | UniswapV3ManagerAggregateInfo>;
}
  
interface BaseAggregateInfo {
    manager: String;
    key: String;
    openInfos: OpenInfo;
}
  
interface GmxManagerAggregateInfo extends BaseAggregateInfo {
    manager: 'Gmx Manager';
    currentInfos: GmxManagerInfo;
}

interface UniswapV3ManagerAggregateInfo extends BaseAggregateInfo {
  manager: 'Uniswap V3 Manager';
  openInfos: UniV3OpenInfo;
  fees: Array<{
    token: string;
    amount: string;
  }>;
  
}
  
interface OpenInfo {}
  
interface UniV3OpenInfo extends OpenInfo {
    liquidity: String;
    feeTier: String;
    tickLower: String;
    tickUpper: String;
    token0: String;
    token1: String;
    amount0: String;
    amount1: String;
    entrySqrtPriceX96: String;
}
  
interface GmxOpenInfo extends OpenInfo {
    collateralToken: String;
    indexToken: String;
    isLong: boolean;
    collateralAmount: String;
    sizeDelta: String;
}
  
interface GmxManagerInfo {
    isOpenSuccess: boolean;
    isCloseSuccess: boolean;
    isLong: boolean;
    contractCollateralAmount: String;
    sizeDelta: String;
    collateral: String;
    averagePrice: String;
    entryFundingRate: String;
    reserveAmount: String;
    realisedPnl: String;
    realisedPnLPositive: boolean;
    lastIncreasedTime: String;
}
  

export async function getPositionsInfos(
    derivioPositionManager: any, 
    accAddr: string
    ): Promise<PositionParse[]> {

    const positions: Position[]  = await derivioPositionManager.getAllPositions(accAddr);
    console.log(positions);
  
    const posList: PositionParse[] = [];
    positions.forEach((position) => {
  
      const pos: PositionParse = {
        positionKey: position.positionKey,
        timestamp: position.timestamp.toString(),
        aggregateInfos: [],
      }
      
      // Iterate through the aggregateInfos within each position
      position.aggregateInfos.forEach((aggregateInfo) => {
        // Check the contract address and parse the feesOf and infoOf accordingly
        if (aggregateInfo.fees.length == 0) {
  
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
              'bool', 
              'bool', 
              'bool', 
              'uint256', 
              'uint256', 
              'uint256', 
              'uint256', 
              'uint256',
              'uint256', 
              'uint256', 
              'bool', 
              'uint256'
            ],
            aggregateInfo.currentInfos
          );
          const gmxManagerInfo: GmxManagerInfo = {
            isOpenSuccess: decodedValues[0],
            isCloseSuccess: decodedValues[1],
            isLong: decodedValues[2],
            contractCollateralAmount: decodedValues[3].toString(),
            sizeDelta: decodedValues[4].toString(),
            collateral: decodedValues[5].toString(),
            averagePrice: decodedValues[6].toString(),
            entryFundingRate: decodedValues[7].toString(),
            reserveAmount: decodedValues[8].toString(),
            realisedPnl: decodedValues[9].toString(),
            realisedPnLPositive: decodedValues[10],
            lastIncreasedTime: decodedValues[11].toString()
          };
  
          const gmxManagerAggregateInfo: GmxManagerAggregateInfo = {
            manager: "Gmx Manager",
            key: aggregateInfo.openResult.key,
            openInfos: gmxOpenInfo,
            currentInfos: gmxManagerInfo,
          };
  
          pos.aggregateInfos.push(gmxManagerAggregateInfo);
          
        } else {
  
          const decodedOpenValues = ethers.utils.defaultAbiCoder.decode(
            [
              'uint256', // liquidity
              'uint256', // feeTier
              'int24',   // tickLower
              'int24',   // tickUpper
              'address', // token0
              'address', // token1
              'uint256', // amount0
              'uint256', // amount1
              'uint160', // entrySqrtPriceX96
            ],
            aggregateInfo.openResult.infos
          );
          const uniV3OpenInfo: UniV3OpenInfo = {
            liquidity: decodedOpenValues[0].toString(),
            feeTier: decodedOpenValues[1].toString(),
            tickLower: decodedOpenValues[2].toString(),
            tickUpper: decodedOpenValues[3].toString(),
            token0: decodedOpenValues[4],
            token1: decodedOpenValues[5],
            amount0: decodedOpenValues[6].toString(),
            amount1: decodedOpenValues[7].toString(),
            entrySqrtPriceX96: decodedOpenValues[8].toString(),
          };
  
          const fees = aggregateInfo.fees.map((fee) => {
            return {
              token: fee[0].toString(),
              amount: fee[1].toString(),
            };
          });
  
          const uniV3ManagerAggregateInfo: UniswapV3ManagerAggregateInfo = {
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


export async function getProductKeeperFee(
  orderManager: any,
  gmxPositionRouter: any,
  productId: number
  ): Promise<string> {
  
  // Support DerivioAL, DerivioFuture
  let keeperFee = await orderManager.keeperFeeOf(productId);
  let gmxExecutionFee = await gmxPositionRouter.minExecutionFee();

  let totalKeeperFee = keeperFee.add(gmxExecutionFee).toString();
  
  return totalKeeperFee;
}


export async function closeDerivioAPositions(
    positionRouter: any,
    positionKeys: BytesLike[],
    values: number[],
    swapToCollateral: boolean,
    token0Address: string,
    token1Address: string
) {
    // Ensure values array has the same length as positionKeys array
    if (positionKeys.length !== values.length) {
        throw new Error("positionKeys and values arrays must have the same length");
    }

    // Map positionKeys and values to CloseArgs array
    const closeArgsList = positionKeys.map((positionKey, index) => ({
        positionKey: positionKey,
        swapToCollateral: swapToCollateral,
    }));

    // Calculate the total value for all positions
    let totalValue = values.reduce((previousValue, currentValue) => previousValue + currentValue, 0);

    return await positionRouter.closeDerivioPosition(closeArgsList, token0Address, token1Address, {
        value: ethers.utils.parseUnits(totalValue.toString(), 18),
    });
}


export async function closeAllPositions(
    positionRouter: any,
    derivioPositionManager: any,
    accAddr: string,
    token0Address: string,
    token1Address: string
  ): Promise<any> {
    const positions: PositionParse[] = await getPositionsInfos(derivioPositionManager, accAddr);
  
    const positionKeys: BytesLike[] = positions.map((position) => position.positionKey);
    const values: number[] = positions.map((position) => {
      // Determine if the position is a GMX position or a UniV3 position
      const isGMXPosition = position.aggregateInfos.some(
        (aggregateInfo) => aggregateInfo.manager === "Gmx Manager"
      );
  
      return isGMXPosition ? 0.0001 : 0;
    });
  
    return await closeDerivioAPositions(
      positionRouter,
      positionKeys,
      values,
      false, // swapToCollateral
      token0Address,
      token1Address
    );
  }