import { expect } from "chai";
import { ethers } from "hardhat";
import hre = require("hardhat");
import { setBalance } from "@nomicfoundation/hardhat-network-helpers";
import {
  IERC20,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";
import { setupContracts } from "../src/setupContracts";
import { fundErc20 } from "../src/fundErc20";
import { swap } from "../src/swap";
import { setPricesWithBitsAndExecute } from "../src/executeGmxPosition";

describe("DerivioA test", function () {
  
  let feeTier = 500;
  
  let owner: any;
  let otherAccount: any;
  let lowerTick: number;
  let upperTick: number;
  let addresses = getAddresses(hre.network.name);
  let uniswapV3Pool: IUniswapV3Pool;
  let swapRouter: ISwapRouter;
  let gmxPositionRouter: IGmxPositionRouter;
  let gmxFastPriceFeed: IGmxFastPriceFeed;
  let weth: IERC20;
  let usdc: IERC20;
  let derivioA: DerivioA;
  let contracts: any;

  // Reuse the same setup in every test.
  beforeEach("Setting contracts", async function () {

    // Contracts are deployed using the first signer/account by default
    [owner, otherAccount] = await ethers.getSigners(); 
    contracts = await setupContracts(feeTier);
    uniswapV3Pool = contracts.uniswapV3Pool;
    swapRouter = contracts.swapRouter;
    gmxPositionRouter = contracts.gmxPositionRouter;
    gmxFastPriceFeed = contracts.gmxFastPriceFeed;
    weth = contracts.weth;
    usdc = contracts.usdc;
    derivioA = contracts.derivioA;
    weth = contracts.weth;
    weth = contracts.weth;
    weth = contracts.weth;
  });

  describe("Deployment", function () {

    it("#1 Should normally open DerivioAS", async function () {
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 20 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(derivioA.address, ethers.constants.MaxUint256);
      await usdc.approve(derivioA.address, ethers.constants.MaxUint256);
      
      await derivioA.openAS({
        recipient: owner.address,
        tickLower: lowerTick,
        tickUpper: upperTick,
        feeTier: feeTier,
        amount0Desired: 0,
        amount1Desired: ethers.utils.parseUnits("1000", 6),
        shortLeverage: 0,
        swapMaxSlippage: 0,
        shortMaxSlippage: 0,
      }, 
      owner.address);

      console.log(await derivioA.positionsOf((await derivioA.getAllPositionIds(owner.address))[0]));
    });

    it("#2 Should normally open DerivioAL", async function () {
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 25 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(derivioA.address, ethers.constants.MaxUint256);
      await usdc.approve(derivioA.address, ethers.constants.MaxUint256);
      
      await derivioA.openAL({
        recipient: owner.address,
        tickLower: lowerTick,
        tickUpper: upperTick,
        feeTier: feeTier,
        amount0Desired: 0,
        amount1Desired: ethers.utils.parseUnits("1000", 6),
        shortLeverage: 500000,
        swapMaxSlippage: 0,
        shortMaxSlippage: 0,
      }, 
      owner.address,
      {value: ethers.utils.parseUnits("0.02", 18)});

      // await setPricesWithBitsAndExecute(owner.address, gmxFastPriceFeed, true, 1500, 1);
      const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
      await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
      await derivioA.getGmxPosition();
    });
    
    it("#3 Should simulate swaps and generate fees", async function () {

      let slot0 = await uniswapV3Pool.slot0();
      console.log('slot0: ' + slot0);
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 20 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(derivioA.address, ethers.constants.MaxUint256);
      await usdc.approve(derivioA.address, ethers.constants.MaxUint256);
      
      await derivioA.openAS({
        recipient: owner.address,
        tickLower: lowerTick,
        tickUpper: upperTick,
        feeTier: feeTier,
        amount0Desired: 0,
        amount1Desired: ethers.utils.parseUnits("1000", 6),
        shortLeverage: 0,
        swapMaxSlippage: 0,
        shortMaxSlippage: 0,
      }, 
      owner.address);

      let positions = await derivioA.getAllPositionIds(owner.address);
      let positionKey = positions[0];

      slot0 = await uniswapV3Pool.slot0();
      console.log('slot0: ' + slot0);

      let [fee0, fee1] = await derivioA.unCollectedFee(positionKey);
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 10000, 6);
      await swap(swapRouter, feeTier, owner, usdc, weth, 10000, 6);

      slot0 = await uniswapV3Pool.slot0();
      console.log('slot0: ' + slot0);

      let comPosition = await derivioA.positionsOf(positionKey);
      await derivioA.collectAllFees(owner.address, positionKey, comPosition.uniV3Position.tokenId);
    });

    it("#4 Should withdraw normally", async function () {

      let slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 20 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(derivioA.address, ethers.constants.MaxUint256);
      await usdc.approve(derivioA.address, ethers.constants.MaxUint256);
      
      await derivioA.openAS({
        recipient: owner.address,
        tickLower: lowerTick,
        tickUpper: upperTick,
        feeTier: feeTier,
        amount0Desired: 0,
        amount1Desired: ethers.utils.parseUnits("1000", 6),
        shortLeverage: 0,
        swapMaxSlippage: 0,
        shortMaxSlippage: 0,
      }, 
      owner.address);

      let positions = await derivioA.getAllPositionIds(owner.address);
      let positionKey = positions[0];

      await fundErc20(usdc, addresses.USDCWhale, owner.address, 10000, 6);
      await swap(swapRouter, feeTier, owner, usdc, weth, 10000, 6);

      await derivioA.withdrawLiquidity(owner.address, positionKey);
    });

  });

});
