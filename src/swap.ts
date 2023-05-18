import { ethers } from "hardhat";
import { getBlockTime } from "./executeGmxPosition";

export async function swap(
  swapRouter: any, 
  feeTier: number, 
  owner: any, 
  tokenIn: any, 
  tokenOut: any, 
  amount: number, 
  decimals: number
  ): Promise<void> {
  
  const amountIn = ethers.utils.parseUnits(String(amount), decimals);
  await tokenIn.approve(swapRouter.address, amountIn);

  await swapRouter.exactInputSingle({
    tokenIn: tokenIn.address,
    tokenOut: tokenOut.address,
    fee: feeTier,
    recipient: owner.address,
    deadline: ethers.constants.MaxUint256,
    amountIn: amountIn,
    amountOutMinimum: ethers.constants.Zero,
    sqrtPriceLimitX96: 0,
  });
};
