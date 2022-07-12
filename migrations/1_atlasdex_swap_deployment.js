var Swap = artifacts.require("./Swap.sol");


module.exports = function(deployer, network) {
  const config = DeploymentConfig[network];
  if (!config) {
    throw Error("deployment config undefined");
  }
  deployer.deploy(Swap, config.nativeWrappedAddress, config.feeCollector);
};
