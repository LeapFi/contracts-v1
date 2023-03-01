import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { ethers } from "ethers";

const {
  ACC_1,
  ACC_2,
  ETHERSCAN_API_KEY,
  ALCHEMY_KEY
} = require("./env.json")

const config: HardhatUserConfig = {
  
  solidity: {
    compilers: [
      {
        version: "0.8.13",
        settings: {
          optimizer: { enabled: true, runs: 200 },
        },
      },
    ],
  },
  
  networks: {
    arbitrum: {
      accounts: [ACC_1],
      chainId: 42161,
      url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`,
    },
    goerli: {
      accounts: [ACC_1],
      chainId: 5,
      url: `https://eth-goerli.g.alchemy.com/v2/${ALCHEMY_KEY}`,
    },
  },

  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
};

export default config;
