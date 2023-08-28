import { ethers } from "hardhat";
import hre = require("hardhat");
import { Signer } from "ethers";
import { ContractFactory, Contract } from "ethers";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
  DerivioFuture,
  DerivioAFactory,
  PositionRouter,
} from "../../typechain";


async function main(): Promise<void> {

  let gmxFastPriceFeed: IGmxFastPriceFeed;
  let addresses = getAddresses(hre.network.name);
  gmxFastPriceFeed = (await ethers.getContractAt("IGmxFastPriceFeed", addresses.GmxFastPriceFeed)) as IGmxFastPriceFeed;

  let timeDeviation = 1000000000;
  const priceGovAddress = await gmxFastPriceFeed.gov();
  const priceGov = await ethers.getSigner(priceGovAddress);
  await gmxFastPriceFeed.connect(priceGov).setMaxTimeDeviation(timeDeviation);

  console.log("timeDeviation:", timeDeviation);
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });