import { ethers } from "hardhat";
import hre = require("hardhat");
import { BigNumber as EthersBigNumber } from "@ethersproject/bignumber"
import { getPriceBits } from "../src/utilities";

export async function setPricesWithBitsAndExecute(
  account: any,
  gmxFastPriceFeed: any, 
  executeOrders: number,
  ): Promise<void> {

  // set price updater
  const priceGovAddress = await gmxFastPriceFeed.gov()
  const priceGov = await ethers.getImpersonatedSigner(priceGovAddress)
  await gmxFastPriceFeed.connect(priceGov).setUpdater(account, true)

  // fill
  const blockTime = await getBlockTime()
  const priceBits = getPriceBits([])

  await gmxFastPriceFeed.setPricesWithBitsAndExecute(
    priceBits,
    blockTime,
    9999999999, // _endIndexForIncreasePositions
    9999999999, // _endIndexForDecreasePositions
    executeOrders, // _maxIncreasePositions
    0 // _maxDecreasePositions
  );
};


async function getBlockTime(): Promise<number> {
  const block = await ethers.provider.getBlock('latest')
  return block.timestamp
}

function toWei(n: string): EthersBigNumber {
  return ethers.utils.parseEther(n)
}
