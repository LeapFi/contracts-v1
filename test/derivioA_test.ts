// import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
// import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { getAddresses, Addresses } from "../src/addresses";
import hre = require("hardhat");
import {
  IERC20,
  IUniswapV3Factory,
  IUniswapV3Pool,
  ISwapRouter,
} from "../typechain";

describe("DerivioA test", function () {
  
  let uniswapV3Pool: IUniswapV3Pool;
  let uniswapV3Factory: IUniswapV3Factory;
  let swapRouter: ISwapRouter;
  let lowerTick: number;
  let upperTick: number;

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployContracts() {

    let addresses = getAddresses(hre.network.name);

    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount] = await ethers.getSigners();

    const UniHelper = await ethers.getContractFactory("UniHelper");
    const uniHelper = await UniHelper.deploy(addresses.UniswapV3Factory);

    const DerivioA = await ethers.getContractFactory("DerivioA");
    const derivioA = await DerivioA.deploy(
      uniHelper.address,
      addresses.UniswapV3Factory,
      addresses.SwapRouter
    );

    uniswapV3Factory = (await ethers.getContractAt(
      "IUniswapV3Factory",
      addresses.UniswapV3Factory,
      owner
    )) as IUniswapV3Factory;

    uniswapV3Pool = (await ethers.getContractAt(
      "IUniswapV3Pool",
      await uniswapV3Factory.getPool(addresses.USDC, addresses.WETH, 500),
      owner
    )) as IUniswapV3Pool;

    swapRouter = (await ethers.getContractAt(
      "ISwapRouter",
      addresses.SwapRouter,
      owner
    )) as ISwapRouter;

    const weth = (await ethers.getContractAt(
      "IERC20",
      addresses.WETH,
      owner
    )) as IERC20;

    // const weth = new ethers.Contract(
    //   addresses.WETH,
    //   [
    //     "function deposit() external payable",
    //     "function sendValue(address payable recipient, uint256 amount)",
    //     "function withdraw(uint256 _amount) external",
    //     "function balanceOf(address account) public view returns (uint256)",
    //     "function approve(address spender, uint256 amount) external returns (bool)",
    //   ],
    //   owner
    // );

    const usdc = (await ethers.getContractAt(
      "IERC20",
      addresses.USDC,
      owner
    )) as IERC20;

    const slot0 = await uniswapV3Pool.slot0();
    const tickSpacing = await uniswapV3Pool.tickSpacing();

    lowerTick = slot0.tick - (slot0.tick % tickSpacing) - tickSpacing;
    upperTick = slot0.tick - (slot0.tick % tickSpacing) + 2 * tickSpacing;
    
    let ab = await ethers.provider.getBalance(owner.address);
    console.log('Balance: ', ab)
    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    let c = 1
    
    const fundErc20 = async (contract: any, sender: any, recepient: any, amount: any, decimals: any) => {

      // await owner.sendTransaction({
      //   to: sender,
      //   value: ethers.utils.parseEther("1"), // Sends exactly 1.0 ether
      //   gasLimit: 10000000,
      // });

      const params = [{
        from: owner.address,
        to: sender,
        value: '10000000' // 1 ether
      }];

      const transactionHash = await ethers.provider.send('eth_sendTransaction', params)

      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [sender],
      });
      
      const FUND_AMOUNT = ethers.utils.parseUnits(amount, decimals);
      // fund erc20 token to the contract
      const whale = await ethers.getSigner(sender);
    
      const contractSigner = contract.connect(whale);
      await contractSigner.transfer(recepient, FUND_AMOUNT);

      await hre.network.provider.request({
        method: "hardhat_stopImpersonatingAccount",
        params: [sender],
      });
    };

    console.log("usdc: " + await usdc.balanceOf('0x905dfcd5649217c42684f23958568e533c711aa3'))
    await fundErc20(usdc, '0x905dfcd5649217c42684f23958568e533c711aa3', owner.address, '1000', 6);
      

    // await hre.network.provider.request({
    //   method: "hardhat_setBalance",
    //   params: [owner.address,
    //     ethers.utils.parseUnits("1", 18)],
    // });

    // await ethers.provider.send("hardhat_setBalance", [
    //     owner.address,
    //     ethers.utils.parseUnits("1", 18),
    //   ]);

    // await weth.sendValue(owner.address, ethers.utils.parseUnits("1", 18));
    // await weth.deposit({ value: ethers.utils.parseUnits("100000", 18) });

    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    let d = 1


    // await hre.network.provider.send("hardhat_setBalance", [
    //     owner.address,
    //     ethers.utils.parseUnits("1", 18),
    //   ]);

    // await swapRouter.exactInputSingle({
    //   tokenIn: addresses.WMATIC,
    //   tokenOut: addresses.USDC,
    //   fee: 500,
    //   recipient: owner.address,
    //   deadline: ethers.constants.MaxUint256,
    //   amountIn: ethers.utils.parseUnits("1000", 18),
    //   amountOutMinimum: ethers.constants.Zero,
    //   sqrtPriceLimitX96: 0,
    // });

    console.log('Balance: ', ab)
    console.log("weth: " + await weth.balanceOf(owner.address) + "  usdc: " + await usdc.balanceOf(owner.address))
    

    let a = 1
  }

  describe("Deployment", function () {
    it("#1 Should normally deployed contracts", async function () {
      await deployContracts();
    });
  });

});
