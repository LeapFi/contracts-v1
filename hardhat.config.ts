import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-gas-reporter";
import { ethers } from "hardhat";
require('dotenv').config();

const acc1 = process.env.PRIVATEKEY_1;
const acc2 = process.env.PRIVATEKEY_2;
const etherscanApiKey = process.env.ETHERSCAN_API_KEY;
const alchemyKey = process.env.ALCHEMY_KEY;
const infuraKey = process.env.INFURA_KEY;


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

    hardhat: {
      chainId: 42161,
      forking: {
        // url: `https://arb-mainnet.g.alchemy.com/v2/${alchemyKey}`,
        url: `https://arbitrum-mainnet.infura.io/v3/${infuraKey}`,
        // url: 'https://testnet.leapfi.io',
        // url: 'http://172.104.111.236:8545',
        blockNumber: 60602557,
      },
      blockGasLimit: 0x1fffffffffff,
      gasPrice: 0,  
      initialBaseFeePerGas: 0,
      allowUnlimitedContractSize: true,
    },

    leapFiTestnet: {
      accounts: acc1 ? [acc1] : [],
      url: 'https://alpha.dev.leapfi.io/',
    },

    arbitrum: {
      accounts: acc1 ? [acc1] : [],
      url: `https://arb-mainnet.g.alchemy.com/v2/${alchemyKey}`,
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
