# LeapFi Smart Contract Repository Integration Guide

This guide explains how to integrate and interact with the LeapFi smart contracts found in the LeapFi/contracts-v1 GitHub repository.

## Prerequisites
Before you begin, make sure you have the following installed:

Node.js (v14.x or later) and
npm (v7.x or later)

---
## Step 1: Clone the Repository
Clone the LeapFi/contracts-v1 repository to your local machine:
```shell
git clone https://github.com/LeapFi/contracts-v1.git
```
---
## Step 2: Install Dependencies
Navigate to the cloned repository's root folder and install the necessary dependencies using npm:

```shell
cd contracts-v1
npm install
```

---
## Step 3: Configure Environment Variables
There are two options for configuring the environment variables:

### Option 1: Rename the env-example.json file (For Compiling Only)
If you only want to compile the .sol files and don't need to run tests or interact with the contracts, you can simply rename the env-example.json file to env.json:

```shell
mv env-example.json env.json
```

### Option 2: Customize env.json with your own keys (For Running Tests)
If you want to run tests or interact with the contracts using your own private key and API keys, create a copy of the env-example.json file and name it env.json:

```shell
cp env-example.json env.json
```
Edit the env.json file to set the appropriate values for your environment. The required variables are:


* ACC_1: Your Ethereum account private key (prefixed with "0x").
* ACC_2: Another Ethereum account private key (prefixed with "0x").
* ETHERSCAN_API_KEY: Your Etherscan API key.
* ALCHEMY_KEY: Your Alchemy API key.
* INFURA_KEY: Your Infura API key.
```json
{
  "ACC_1": "0xYOUR_PRIVATE_KEY_1",
  "ACC_2": "0xYOUR_PRIVATE_KEY_2",
  "ETHERSCAN_API_KEY": "your-etherscan-api-key",
  "ALCHEMY_KEY": "your-alchemy-api-key",
  "INFURA_KEY": "your-infura-api-key"
}
```
Note: Make sure to keep your private keys secure and never share them publicly. Additionally, don't commit the env.json file to any public repositories.

---
## Step 4: Compile Smart Contracts
Compile the smart contracts using Hardhat:

```shell
npx hardhat compile
```
This command will compile the contracts and generate the corresponding build artifacts.

Running Tests
To run tests, use the following command:

```shell
npx hardhat test
```
Please note that you need to configure the env.json file with your own private key and API keys (Option 2 in Step 3) in order to run tests.

Interacting with the Smart Contracts
Now that you've successfully set up the repository, compiled the contracts, and optionally configured the environment for testing, you can deploy and interact with the contracts using Hardhat scripts or your preferred tools for development.