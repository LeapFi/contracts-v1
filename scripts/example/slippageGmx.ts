import hre = require("hardhat");
import { ethers } from "hardhat";
import { getAddresses } from "../../src/addresses";
import {
  IERC20,
  IPositionRouter,
  DerivioPositionManager,
} from "../../typechain";
import { getPositionsInfos } from "../../src/position";

// Helper function to wait for a certain amount of time
function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main(): Promise<void> {

  const addresses = getAddresses(hre.network.name);
  const [owner] = await ethers.getSigners();
  const userAddr = owner.address;

  const weth = (await ethers.getContractAt("IERC20", addresses.WETH)) as IERC20;
  const usdc = (await ethers.getContractAt("IERC20", addresses.USDC)) as IERC20;
  const positionRouter = (await ethers.getContractAt("IPositionRouter", addresses.LeapPositionRouter)) as IPositionRouter;
  const derivioPositionManager = await ethers.getContractAt("DerivioPositionManager", addresses.DerivioPositionManager) as DerivioPositionManager;
  
  await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
  
  const isLong = true;
  const collateralAmount = 500;
  const leverage = 2;
  let value = ethers.utils.parseUnits("0.0001", 18);

  const collateralAmountIn = ethers.utils.parseUnits(collateralAmount.toString(), 6);
  const sizeDelta = ethers.utils.parseUnits((collateralAmount * leverage).toString(), 6);

  await positionRouter.openDerivioFuturePositions([
    {
      recipient: owner.address,
      value: value,
      isLong: isLong,
      collateralAmount: collateralAmountIn,
      sizeDelta: sizeDelta,
      acceptPrice: isLong ? ethers.utils.parseUnits("1000", 30) : 0,
    }],
    usdc.address,
    weth.address,
    { value: value }
  );
  
  // Due to slippage limit, pending order executed fail
  // "currentInfos": {
  //   "isOpenSuccess": false,                           <--- false
  //   "contractCollateralAmount": "500000000",          <--- will not equal to 0

  // Need to close the position if want to refund the collateral

  // Get all positions in user
  console.log('positionsInfos:', JSON.stringify(await getPositionsInfos(derivioPositionManager, owner.address), null, 2));
  console.log("weth:", await weth.balanceOf(userAddr), "usdc:", await usdc.balanceOf(userAddr));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
});

