const HDWalletProvider = require("@truffle/hdwallet-provider");
require('dotenv').config();
const fs = require("fs");

function prepareConfig() {
  // expected config path
  const configPath = `${__dirname}/deployment_config.js`;

  // create dummy object if deployment config doesn't exist
  // for compilation purposes
  if (fs.existsSync(configPath)) {
    DeploymentConfig = require(configPath);
  } else {
    DeploymentConfig = {};
  }
}
prepareConfig();

module.exports = {
  compilers: {
       solc: {
          version: "^0.8.4",
          settings: {
            optimizer: {
              enabled: true,
              runs: 200
            }
          }
       }
  },
  // See <http://truffleframework.com/docs/advanced/configuration>
  // for more about customizing your Truffle configuration!
  networks: {
    development: {
      host: "127.0.0.1",
      port: 7545,
      network_id: "*" // Match any network id
    },
    develop: {
      port: 8545
    },
    rinkeby: {
      provider: function() {
        return new HDWalletProvider(
          DeploymentConfig["rinkeby"].mnemonic,
          DeploymentConfig["rinkeby"].rpc
        )
      },
      network_id: 4,
    },

    mainnet: {
      provider: function() {
        return new HDWalletProvider(
          DeploymentConfig["mainnet"].mnemonic,
          DeploymentConfig["mainnet"].rpc
        )
      },
      network_id: 1,
      confirmations: 1,
      timeoutBlocks: 200,
      skipDryRun: false,
    },
    
    polygon: {
      provider: function() {
        return new HDWalletProvider(
          process.env.PRIVATE_KEY, 
          process.env.WEB3_HTTP_PROVIDER_POLYGON_MAINNET
        )
      },
      network_id: 137,
      gasPrice: 40000000000,
    },
    polygon_testnet: {
      provider: function() {
        return new HDWalletProvider(process.env.PRIVATE_KEY, process.env.WEB3_HTTP_PROVIDER_POLYGON_TESTNET)
      },
      network_id: 80001
    },

    binance_test: {
      provider: function() {
        return new HDWalletProvider(process.env.MNEMONIC, process.env.WEB3_HTTP_PROVIDER_BINANCE_TEST)
      },
      network_id: 97
    },
    binance: {
      provider: function() {
        return new HDWalletProvider(process.env.PRIVATE_KEY, process.env.WEB3_HTTP_PROVIDER_BINANCE_MAINNET)
      },
      network_id: 56,
      skipDryRun: true,
    },   
    avax: {
      provider: function() {
        return new HDWalletProvider(process.env.PRIVATE_KEY, process.env.WEB_HTTP_PROVIDER_AVAX_MAINNET)
      },
      network_id: 43114,
      gasPrice: 90000000000,
      skipDryRun: true,
    },
  },

  plugins: ['truffle-plugin-verify'],
  api_keys: {
    bscscan: process.env.BSCSCAN_API_KEY,
    etherscan: process.env.ETHERSCAN_API_KEY,
    polygonscan: process.env.POLYGONSCAN_API_KEY,
  }
};
