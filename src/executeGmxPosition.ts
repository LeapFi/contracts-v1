import { ethers } from "hardhat";
import hre = require("hardhat");
import {
  IGmxPositionRouter,
} from "../typechain";

export async function executeIncrease(
  gmxPositionRouter: IGmxPositionRouter, 
  derivioTrader: any,
  keeperAddress: any, 
  ): Promise<void> {

  await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [keeperAddress],
  });

  console.log("Account Balance");
  console.log(await ethers.provider.getBalance(keeperAddress));

  console.log("waitingPositionsLength");
  console.log(await waitingPositionsLength(gmxPositionRouter, true));

  await gmxPositionRouter.executeIncreasePositions(
    await waitingPositionsLength(gmxPositionRouter, true),
    derivioTrader.address
  );
 
  await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [keeperAddress],
  });
};

export async function setPricesWithBitsAndExecute(
  gmxFastPriceFeed: any, 
  priceUpdater: any, 
  priceBits: any,
  blockTime: any,
  ): Promise<void> {

  // await hre.network.provider.request({
  //   method: "hardhat_impersonateAccount",
  //   params: [priceUpdater],
  // });

  await gmxFastPriceFeed.setPricesWithBitsAndExecute(
    priceBits,
    blockTime,
    9999999999, // _endIndexForIncreasePositions
    9999999999, // _endIndexForDecreasePositions
    1, // _maxIncreasePositions
    0 // _maxDecreasePositions
  );

  // await hre.network.provider.request({
  //   method: "hardhat_stopImpersonatingAccount",
  //   params: [priceUpdater],
  // });
};

async function waitingPositionsLength(
  gmxPositionRouter: IGmxPositionRouter, 
  isIncrease: any, 
  ): Promise<string> {

  let a = isIncrease ? 1 : 3;
  return (
    await gmxPositionRouter.getRequestQueueLengths()
  )[a].toString();
};
