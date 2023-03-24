import { ethers } from "hardhat";

export async function swap(
  swapRouter: any, 
  feeTier: number, 
  owner: any, 
  tokenIn: any, 
  tokenOut: any, 
  amount: number, 
  decimals: number
  ): Promise<void> {

  await tokenIn.approve(swapRouter.address, ethers.utils.parseUnits(String(amount), decimals));
  await swapRouter.exactInputSingle({
    tokenIn: tokenIn.address,
    tokenOut: tokenOut.address,
    fee: feeTier,
    recipient: owner.address,
    deadline: ethers.constants.MaxUint256,
    amountIn: ethers.utils.parseUnits(String(amount), decimals),
    amountOutMinimum: ethers.constants.Zero,
    sqrtPriceLimitX96: 0,
  });
};
