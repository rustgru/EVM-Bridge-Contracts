var AtlasDexSwap = artifacts.require("./Swap.sol");

const DeploymentConfig = require(`${__dirname}/../deployment_config.js`);

module.exports = function(deployer, network) {
  const config = DeploymentConfig[network];
  if (!config) {
    throw Error("deployment config undefined");
  }
  deployer.deploy(AtlasDexSwap, config.nativeWrappedAddress, config.feeCollector);
};
