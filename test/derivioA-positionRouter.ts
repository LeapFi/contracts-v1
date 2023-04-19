import { expect } from "chai";
import { ethers } from "hardhat";
import hre = require("hardhat");
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
  IGmxPositionRouter,
  IGmxFastPriceFeed,
  DerivioA,
  DerivioPositionManager,
  IPositionRouter,
} from "../typechain";
import { getAddresses, Addresses } from "../src/addresses";
import { setupContracts } from "../src/setupContracts";
import { fundErc20 } from "../src/fundErc20";
import { setPricesWithBitsAndExecute } from "../src/executeGmxPosition";

describe("DerivioA test", function () {
  
  let feeTier = 500;
  
  let owner: any;
  let otherAccount: any;
  let lowerTick: number;
  let upperTick: number;
  let addresses = getAddresses(hre.network.name);
  let uniswapV3Factory: IUniswapV3Factory;
  let uniswapV3Pool: IUniswapV3Pool;
  let swapRouter: ISwapRouter;
  let gmxPositionRouter: IGmxPositionRouter;
  let gmxFastPriceFeed: IGmxFastPriceFeed;
  let weth: IERC20;
  let usdc: IERC20;
  let derivioA: DerivioA;
  let positionRouter: IPositionRouter;
  let derivioPositionManager: DerivioPositionManager;
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
    positionRouter = contracts.positionRouter;
    derivioPositionManager = contracts.derivioPositionManager;
  });

  describe("PositionRouter control flow", function () {

    it("#1 open DerivioAS by Position Router", async function () {
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();

      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 25 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
      
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
      await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
      await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);

      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      
      await positionRouter.openDerivioA(
        {
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
        weth.address,
        usdc.address,
      );

      console.log(await derivioPositionManager.getAllPositions(owner.address));

      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
      console.log(174031535328595519 - 173260603813924286);
      // (await derivioPositionManager.getAllPositions(owner.address)).forEach((position, index) => {
      //   console.log(`Position #${index + 1}:`);
      //   console.log(`  Position Key: ${position.positionKey}`);
      //   position.protocolPosition.forEach((protocolPosition, protocolIndex) => {
      //     console.log(`  Protocol Position #${protocolIndex + 1}:`);
      //     console.log(`    Protocol Vault: ${protocolPosition.protocolVault}`);
      //     console.log(`    Position Info: ${protocolPosition.positionInfo}`);
      //   });
      // });
    });

    // it("#2 open DerivioAL by Position Router", async function () {
    //   const slot0 = await uniswapV3Pool.slot0();
    //   const tickSpacing = await uniswapV3Pool.tickSpacing();

    //   lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 25 * tickSpacing;
    //   upperTick = slot0.tick - (slot0.tick % tickSpacing) + 10 * tickSpacing;
      
    //   await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
    //   await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
    //   await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
      
    //   await positionRouter.openDerivioA(
    //     {
    //       recipient: owner.address,
    //       tickLower: lowerTick,
    //       tickUpper: upperTick,
    //       feeTier: feeTier,
    //       amount0Desired: 0,
    //       amount1Desired: ethers.utils.parseUnits("1000", 6),
    //       shortLeverage: 500000,
    //       swapMaxSlippage: 0,
    //       shortMaxSlippage: 0,
    //     },
    //     weth.address,
    //     usdc.address,
    //     {value: ethers.utils.parseUnits("0.02", 18)}
    //   );

    //   // await setPricesWithBitsAndExecute(owner.address, gmxFastPriceFeed, 1700, true, 1);
    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
    //   await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   console.log(await derivioPositionManager.getAllPositions(owner.address));
    //   await positionRouter.getGmxPosition(weth.address, usdc.address);
    // });

    it("#3 close DerivioAS by Position Router", async function () {
      const slot0 = await uniswapV3Pool.slot0();
      const tickSpacing = await uniswapV3Pool.tickSpacing();
  
      lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 250 * tickSpacing;
      upperTick = slot0.tick - (slot0.tick % tickSpacing) + 100 * tickSpacing;
  
      await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
  
      await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
      await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
  
      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
  
      await positionRouter.openDerivioA(
          {
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
          weth.address,
          usdc.address
      );
  
      // Use getAllPositions to retrieve the positions
      const positions = await derivioPositionManager.getAllPositions(owner.address);
      const positionKeys = positions.map(pos => pos.positionKey);

      await positionRouter.closeDerivioA([positionKeys[0]], 'true', weth.address, usdc.address);
      
      // Get updated positions after closing
      const newPositions = await derivioPositionManager.getAllPositions(owner.address);
      const newPositionKeys = newPositions.map(pos => pos.positionKey);
  
      expect(newPositionKeys.length).to.equal(positionKeys.length - 1);

      console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    });

    // it("#4 close DerivioAL by Position Router", async function () {
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    //   const slot0 = await uniswapV3Pool.slot0();
    //   const tickSpacing = await uniswapV3Pool.tickSpacing();

    //   lowerTick = slot0.tick - (slot0.tick % tickSpacing) - 250 * tickSpacing;
    //   upperTick = slot0.tick - (slot0.tick % tickSpacing) + 100 * tickSpacing;
      
    //   await fundErc20(usdc, addresses.USDCWhale, owner.address, 1000, 6);
      
    //   await weth.approve(positionRouter.address, ethers.constants.MaxUint256);
    //   await usdc.approve(positionRouter.address, ethers.constants.MaxUint256);
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
      
    //   await positionRouter.openDerivioA(
    //     {
    //       recipient: owner.address,
    //       tickLower: lowerTick,
    //       tickUpper: upperTick,
    //       feeTier: feeTier,
    //       amount0Desired: 0,
    //       amount1Desired: ethers.utils.parseUnits("1000", 6),
    //       shortLeverage: 500000,
    //       swapMaxSlippage: 0,
    //       shortMaxSlippage: 0,
    //     },
    //     weth.address,
    //     usdc.address,
    //     {value: ethers.utils.parseUnits("0.02", 18)}
    //   );
      
    //   // Use getAllPositions to retrieve the positions
    //   const positions = await derivioPositionManager.getAllPositions(owner.address);
    //   const positionKeys = positions.map(pos => pos.positionKey);

    //   await positionRouter.closeDerivioA([positionKeys[0]], weth.address, usdc.address, {value: ethers.utils.parseUnits("0.0001", 18)});

    //   const positionKeeper = await ethers.getImpersonatedSigner(addresses.GMXFastPriceFeed);
    //   await gmxPositionRouter.connect(positionKeeper).executeIncreasePositions(999999999, addresses.GMXFastPriceFeed);
    //   await gmxPositionRouter.connect(positionKeeper).executeDecreasePositions(999999999, addresses.GMXFastPriceFeed);

    //   // Get updated positions after closing
    //   const newPositions = await derivioPositionManager.getAllPositions(owner.address);
    //   const newPositionKeys = newPositions.map(pos => pos.positionKey);

    //   expect(newPositionKeys.length).to.equal(positionKeys.length - 1);
      
    //   console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address));
    //   await positionRouter.getGmxPosition(weth.address, usdc.address);
    // });

  });

});
