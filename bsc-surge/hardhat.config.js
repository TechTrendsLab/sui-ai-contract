require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const accounts = [process.env.PRIVATE_KEY, process.env.PRIVATE_KEY_2].filter((key) => key !== undefined);

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    hardhat: {
      chainId: 1337
    },
    bsc: {
      //url: "https://bsc-dataseed1.binance.org/",
      url:"https://bnb-testnet.g.alchemy.com/v2/KS5hJx7LOvIvc5jj9ybf9",
      chainId: 56,
      accounts
    },
    bscTestnet: {
      url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
      //url:"https://bnb-testnet.g.alchemy.com/v2/KS5hJx7LOvIvc5jj9ybf9",
      chainId: 97,
      accounts
    },
    sepolia: {
      url: "https://eth-sepolia.g.alchemy.com/v2/KS5hJx7LOvIvc5jj9ybf9",
      chainId: 11155111,
      accounts
    }
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts"
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD",
    outputFile: "gas-report.txt",
    noColors: true,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  }
};

