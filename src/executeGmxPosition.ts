import { ethers } from "hardhat";
import hre = require("hardhat");
import { BigNumber as EthersBigNumber } from "@ethersproject/bignumber"
import { getPriceBits } from "../src/utilities";
import {
  IGmxFastPriceFeed,
  IGmxPositionRouter,
} from "../typechain";

export async function setPricesWithBitsAndExecute(
  account: any,
  gmxFastPriceFeed: IGmxFastPriceFeed,
  isIncrease: boolean,
  price: number,
  executeOrders: number,
  ): Promise<void> {

  // set price updater
  const priceGovAddress = await gmxFastPriceFeed.gov();
  const priceGov = await ethers.getImpersonatedSigner(priceGovAddress);
  await gmxFastPriceFeed.connect(priceGov).setUpdater(account, true);
  
  // random price
  let min = 1600;
  let max = 1610;
  let randomPrice = Math.floor(Math.random() * (max - min + 1) + min).toString();
  // randomPrice = price.toString();

  // fill
  const blockTime = await getBlockTime();
  const priceBits = getPriceBits([]);
  
  // let requestQue = await gmxPositionRouter.getRequestQueueLengths();
  // await gmxFastPriceFeed.setPricesWithBitsAndExecute(priceBits, blockTime, 9999999999, 9999999999, 0, executeOrders);
  // await gmxFastPriceFeed.setPricesWithBitsAndExecute(priceBits, blockTime, 9999999999, 9999999999, executeOrders, 0);

  if (isIncrease) {
    let tx = await gmxFastPriceFeed.setPricesWithBitsAndExecute(
      priceBits,
      blockTime,
      9999999999, // _endIndexForIncreasePositions
      9999999999, // _endIndexForDecreasePositions
      executeOrders, // _maxIncreasePositions
      0 // _maxDecreasePositions
    );

    // const receipt = await tx.wait();
    // for (const event of receipt.events || []) {
    //   try {
    //     const parsedEvent = gmxFastPriceFeed.interface.parseLog(event);
    //     console.log(`Event name: ${parsedEvent.name}`);
    //     console.log(`Event args: ${JSON.stringify(parsedEvent.args, null, 2)}`);
    //     console.log("----");
    //   } 
    //   catch (error) {
    //     console.log("Unrecognized event:", event);
    //   };
    // }

  }
  else {
    let tx = await gmxFastPriceFeed.setPricesWithBitsAndExecute(
      priceBits,
      blockTime,
      9999999999, // _endIndexForIncreasePositions
      9999999999, // _endIndexForDecreasePositions
      0, // _maxIncreasePositions
      executeOrders // _maxDecreasePositions
    );
    
    // const receipt = await tx.wait();
    // for (const event of receipt.events || []) {
    //   try {
    //     const parsedEvent = gmxFastPriceFeed.interface.parseLog(event);
    //     console.log(`Event name: ${parsedEvent.name}`);
    //     console.log(`Event args: ${JSON.stringify(parsedEvent.args, null, 2)}`);
    //     console.log("----");
    //   } 
    //   catch (error) {
    //     console.log("Unrecognized event:", event);
    //   };
    // }
  }
  
};


export async function getBlockTime(): Promise<number> {
  const block = await ethers.provider.getBlock('latest');
  return block.timestamp;
}

function toWei(n: string): EthersBigNumber {
  return ethers.utils.parseEther(n);
}
