import { ethers } from "hardhat";
import hre = require("hardhat");
import {  setBalance } from "@nomicfoundation/hardhat-network-helpers"

export async function fundErc20(token: any, sender: any, recipient: any, amount: number, decimals: number): Promise<void> {

  const fundAmount = ethers.utils.parseUnits(String(amount), decimals)
  
  // // transfer funding to recipient
  const whale = await ethers.getImpersonatedSigner(sender)
  await setBalance(sender, ethers.utils.parseUnits("1000", 30))
  await token.connect(whale).transfer(recipient, fundAmount)
};
