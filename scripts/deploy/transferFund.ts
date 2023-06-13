import { ethers } from "hardhat";
import hre = require("hardhat");
import { Signer } from "ethers";
import { getAddresses } from "../../src/addresses";
import {
    IERC20,
  } from "../../typechain";
import { fundErc20 } from "../../src/fundErc20";


async function main(): Promise<void> {

  let owner: Signer;
  let otherAccount: Signer;
  let weth: IERC20;
  let usdc: IERC20;

  let addresses = getAddresses(hre.network.name);
  [owner, otherAccount] = await ethers.getSigners();

  weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
  
  let fundingAddr = '0x5960F23Edbb278514411Db9ef66f787e33612cbA';
  
  console.log('fundingAddr: ' + fundingAddr);
  console.log('balanceOf: ' + await usdc.balanceOf(fundingAddr));
  await fundErc20(usdc, '0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8', fundingAddr, 100000, 6);
  console.log('balanceOf: ' + await usdc.balanceOf(fundingAddr));
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
});