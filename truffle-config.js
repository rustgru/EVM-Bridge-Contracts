const HDWalletProvider = require("@truffle/hdwallet-provider");
require('dotenv').config();

module.exports = {
  compilers: {
       solc: {
          version: "^0.8.0"
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
        return new HDWalletProvider(process.env.PRIVATE_KEY, process.env.WEB3_HTTP_PROVIDER_RINKEBY)
      },
      network_id: 4,
    },
    
    ropsten: {
      provider: function() {
        return new HDWalletProvider(process.env.PRIVATE_KEY, process.env.WEB3_HTTP_PROVIDER_ROPSTEN)
      },
      network_id: 3,
      //from: ''
    },

    mainnet: {
      provider: function() {
        return new HDWalletProvider(process.env.PRIVATE_KEY, process.env.WEB3_HTTP_PROVIDER_MAINNET)
      },
      network_id: 1
    },
    
    polygon_mainnet: {
      provider: function() {
        return new HDWalletProvider(process.env.PRIVATE_KEY, process.env.WEB3_HTTP_PROVIDER_POLYGON_MAINNET)
      },
      network_id: 137
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
        return new HDWalletProvider(process.env.MNEMONIC, process.env.WEB3_HTTP_PROVIDER_BINANCE_MAINNET)
      },
      network_id: 56,
      gasPrice: 10000000000,
      skipDryRun: true,
    },
  },

  plugins: ["truffle-contract-size", "truffle-plugin-verify"],
  api_keys: {
    bscscan: process.env.BSCSCAN_API_KEY,
    etherscan: process.env.ETHERSCAN_API_KEY,
  }
};
