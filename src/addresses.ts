/* eslint-disable @typescript-eslint/naming-convention */
export interface Addresses {
  UniswapV3Factory: string;
  SwapRouter: string;
  NonfungiblePositionManager: string;
  GmxRouter: string;
  GmxPositionRouter: string;
  GmxPositionManager: string;
  GmxVault: string;
  GmxKeeper: string;
  GmxFastPriceFeed: string;
  GmxEthPriceFeed: string;
  GmxLiquidator: string;
  CrvUSDController: string;
  WETH: string;
  USDC: string;
  USDCWhale: string;
  LeapPositionRouter: string;
  DerivioPositionManager: string;
  OrderManager: string;
}

export const getAddresses = (network: string): Addresses => {
  switch (network) {
    case "hardhat":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        GmxRouter: "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064",
        GmxPositionRouter: "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868",
        GmxPositionManager: "0x75e42e6f01baf1d6022bea862a28774a9f8a4a0c",
        GmxVault: "0x489ee077994B6658eAfA855C308275EAd8097C4A",
        GmxKeeper: "0xdd763ed8ce604e9a61f1e1aed433c1362e05700d",
        GmxFastPriceFeed: "0x11d62807dae812a0f1571243460bf94325f43bb7",
        GmxEthPriceFeed: "0x3607e46698d218B3a5Cae44bF381475C0a5e2ca7",
        GmxLiquidator: "0x44311c91008DDE73dE521cd25136fD37d616802c",
        CrvUSDController: "0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "0x905dfcd5649217c42684f23958568e533c711aa3",
        LeapPositionRouter: "",
        DerivioPositionManager: "",
        OrderManager: "",
      };
    case "leapFiTestnet":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        GmxRouter: "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064",
        GmxPositionRouter: "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868",
        GmxPositionManager: "0x75e42e6f01baf1d6022bea862a28774a9f8a4a0c",
        GmxVault: "0x489ee077994B6658eAfA855C308275EAd8097C4A",
        GmxKeeper: "0xdd763ed8ce604e9a61f1e1aed433c1362e05700d",
        GmxFastPriceFeed: "0x11d62807dae812a0f1571243460bf94325f43bb7",
        GmxEthPriceFeed: "0x3607e46698d218B3a5Cae44bF381475C0a5e2ca7",
        GmxLiquidator: "0x44311c91008DDE73dE521cd25136fD37d616802c",
        CrvUSDController: "0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "0x905dfcd5649217c42684f23958568e533c711aa3",
        LeapPositionRouter: "0xd18CF0194a2A35FE6436Dd8D723B03F405b58a17",
        DerivioPositionManager: "0x44Fd5c224F5988462Df1E2d176Bfb5489907D825",
        OrderManager: "0x1D16BD123B76b49191B5E0eb61cb3128D666Af50",
      };
    case "arbitrum":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        GmxRouter: "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064",
        GmxPositionRouter: "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868",
        GmxPositionManager: "0x75e42e6f01baf1d6022bea862a28774a9f8a4a0c",
        GmxVault: "0x489ee077994B6658eAfA855C308275EAd8097C4A",
        GmxKeeper: "0xdd763ed8ce604e9a61f1e1aed433c1362e05700d",
        GmxFastPriceFeed: "0x11d62807dae812a0f1571243460bf94325f43bb7",
        GmxEthPriceFeed: "0x3607e46698d218B3a5Cae44bF381475C0a5e2ca7",
        GmxLiquidator: "0x44311c91008DDE73dE521cd25136fD37d616802c",
        CrvUSDController: "0x100dAa78fC509Db39Ef7D04DE0c1ABD299f4C6CE",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "",
        LeapPositionRouter: "",
        DerivioPositionManager: "",
        OrderManager: "",
      };
    default:
      throw new Error(`No addresses for Network: ${network}`);
  }
};
