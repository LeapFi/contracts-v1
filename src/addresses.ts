/* eslint-disable @typescript-eslint/naming-convention */
export interface Addresses {
  UniswapV3Factory: string;
  SwapRouter: string;
  NonfungiblePositionManager: string;
  WETH: string;
  USDC: string;
  USDCWhale: string;
}

export const getAddresses = (network: string): Addresses => {
  switch (network) {
    case "hardhat":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "0x905dfcd5649217c42684f23958568e533c711aa3",
      };
    case "arbitrum":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "",
      };
    default:
      throw new Error(`No addresses for Network: ${network}`);
  }
};
