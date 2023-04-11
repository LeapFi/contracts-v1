/* eslint-disable @typescript-eslint/naming-convention */
export interface Addresses {
  UniswapV3Factory: string;
  SwapRouter: string;
  NonfungiblePositionManager: string;
  GMXRouter: string;
  GMXPositionRouter: string;
  GMXVault: string;
  GMXKeeper: string;
  GMXFastPriceFeed: string;
  WETH: string;
  USDC: string;
  USDCWhale: string;
  LeapPositionRouter: string;
}

export const getAddresses = (network: string): Addresses => {
  switch (network) {
    case "hardhat":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        GMXRouter: "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064",
        GMXPositionRouter: "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868",
        GMXVault: "0x489ee077994B6658eAfA855C308275EAd8097C4A",
        GMXKeeper: "0xdd763ed8ce604e9a61f1e1aed433c1362e05700d",
        GMXFastPriceFeed: "0x11d62807dae812a0f1571243460bf94325f43bb7",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "0x905dfcd5649217c42684f23958568e533c711aa3",
        LeapPositionRouter: "0xEd911Fc9e5C4478ef2D3e46eaaCbe345ECC6E5B4",
      };
    case "arbitrumForked":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        GMXRouter: "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064",
        GMXPositionRouter: "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868",
        GMXVault: "0x489ee077994B6658eAfA855C308275EAd8097C4A",
        GMXKeeper: "0xdd763ed8ce604e9a61f1e1aed433c1362e05700d",
        GMXFastPriceFeed: "0x11d62807dae812a0f1571243460bf94325f43bb7",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "0x905dfcd5649217c42684f23958568e533c711aa3",
        LeapPositionRouter: "0xEd911Fc9e5C4478ef2D3e46eaaCbe345ECC6E5B4",
      };
    case "arbitrum":
      return {
        UniswapV3Factory: "0x1F98431c8aD98523631AE4a59f267346ea31F984",
        SwapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
        NonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
        GMXRouter: "0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064",
        GMXPositionRouter: "0xb87a436B93fFE9D75c5cFA7bAcFff96430b09868",
        GMXVault: "0x489ee077994B6658eAfA855C308275EAd8097C4A",
        GMXKeeper: "0xdd763ed8ce604e9a61f1e1aed433c1362e05700d",
        GMXFastPriceFeed: "0x11d62807dae812a0f1571243460bf94325f43bb7",
        WETH: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        USDC: "0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8",
        USDCWhale: "",
        LeapPositionRouter: "",
      };
    default:
      throw new Error(`No addresses for Network: ${network}`);
  }
};
