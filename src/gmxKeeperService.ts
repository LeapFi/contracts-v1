// import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import hre = require("hardhat");
import {
  IGmxFastPriceFeed,
} from "../typechain";
import { getAddresses } from "../src/addresses";
import { fundErc20 } from "../src/fundErc20";
import { getPriceBits } from "./utilities";


// ... (other imports and declarations)

async function main() {
    
    let owner: any;
    let gmxFastPriceFeed: IGmxFastPriceFeed;
    let addresses = getAddresses(hre.network.name);

    [owner] = await ethers.getSigners();
    gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GMXFastPriceFeed)) as IGmxFastPriceFeed;

    await setPricesUpdater(owner.address, gmxFastPriceFeed);
    
    setInterval(async () => {
      try {
        console.log("Execute setPricesWithBitsAndExecute");
        await setPricesWithBitsAndExecute(owner.address, gmxFastPriceFeed);
      } catch (error) {
        console.error("Error in setPricesWithBitsAndExecute:", error);
      }
    }, 10000); // Call every 10 seconds (10000 milliseconds)
}

export async function setPricesWithBitsAndExecute(
    account: any,
    gmxFastPriceFeed: IGmxFastPriceFeed,
    ): Promise<void> {
  
    // set price updater
    const priceGovAddress = await gmxFastPriceFeed.gov()
    const priceGov = await ethers.getImpersonatedSigner(priceGovAddress)
    await gmxFastPriceFeed.connect(priceGov).setUpdater(account, true)
    
    // random price
    let min = 1625;
    let max = 1645;
    let randomPrice = Math.floor(Math.random() * (max - min + 1) + min).toString();
    // randomPrice = price.toString();
  
    // fill
    const blockTime = await getBlockTime();
    const priceBits = getPriceBits([randomPrice, randomPrice, randomPrice, randomPrice]);
  
    await gmxFastPriceFeed.setPricesWithBitsAndExecute(
        priceBits,
        blockTime,
        9999999999, // _endIndexForIncreasePositions
        9999999999, // _endIndexForDecreasePositions
        1000, // _maxIncreasePositions
        1000 // _maxDecreasePositions
    );
};

export async function setPricesUpdater(
    account: any,
    gmxFastPriceFeed: IGmxFastPriceFeed,
    ): Promise<void> {
  
    // set price updater
    const priceGovAddress = await gmxFastPriceFeed.gov()
    const priceGov = await ethers.getImpersonatedSigner(priceGovAddress)
    await gmxFastPriceFeed.connect(priceGov).setUpdater(account, true)
};


async function getBlockTime(): Promise<number> {
    const block = await ethers.provider.getBlock('latest')
    return block.timestamp
}
  
  
main()
.then(() => console.log("Script started"))
.catch((error) => {
    console.error("Error in the main function:", error);
    process.exit(1);
});
