import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";
import { ethers } from "hardhat";


const {
  ACC_1,
  ACC_2,
  ETHERSCAN_API_KEY,
  ALCHEMY_KEY,
  INFURA_KEY
} = require("./env.json")

const config: HardhatUserConfig = {
  
  solidity: {
    compilers: [
      {
        version: "0.8.13",
        settings: {
          optimizer: { enabled: true, runs: 20 },
        },
      },
    ],
  },

  networks: {

    hardhat: {
      chainId: 42161,
      forking: {
        url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`,
        // url: `https://arbitrum-mainnet.infura.io/v3/${INFURA_KEY}`,
        // url: 'https://testnet.leapfi.io',
        // url: 'http://172.104.111.236:8545',
        blockNumber: 71602557,
      },
      blockGasLimit: 0x1fffffffffff,
      gasPrice: 0,  
      initialBaseFeePerGas: 0,
      allowUnlimitedContractSize: true,
    },

    arbitrumForked: {
      accounts: ACC_1 ? [ACC_1] : [],
      url: 'https://testnet.leapfi.io',
    },

    arbitrum: {
      accounts: ACC_1 ? [ACC_1] : [],
      url: `https://arb-mainnet.g.alchemy.com/v2/${ALCHEMY_KEY}`,
    },
  },

  gasReporter: {
    enabled: true,
    currency: "USD",
    gasPrice: 1,
  },

  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
};

export default config;
