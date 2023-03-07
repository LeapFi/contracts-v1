import { ethers } from "hardhat";
import hre = require("hardhat");

export async function fundErc20(token: any, sender: any, recipient: any, amount: number, decimals: number): Promise<void> {

  await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [sender],
  });

  // transfer funding to recipient
  const fundAmount = ethers.utils.parseUnits(String(amount), decimals);
  const whale = await ethers.getSigner(sender);
  await token.connect(whale).transfer(recipient, fundAmount);
 
  await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [sender],
  });
};
