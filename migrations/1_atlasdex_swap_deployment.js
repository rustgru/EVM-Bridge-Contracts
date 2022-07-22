var AtlasDexSwapImplementation = artifacts.require("AtlasDexSwapImplementation")
var AtlasDexSwapSetup = artifacts.require("AtlasDexSwapSetup");
var AtlasDexSwapProxy = artifacts.require("AtlasDexSwapProxy")
const DeploymentConfig = require(`${__dirname}/../deployment_config.js`);

module.exports = async function(deployer, network) {
  const config = DeploymentConfig[network];
  if (!config) {
    throw Error("deployment config undefined");
  }

  await deployer.deploy(AtlasDexSwapImplementation);

  if (!config.deployImplementationOnly) {
    // deploy conductor setup
    await deployer.deploy(AtlasDexSwapSetup);

    // encode initialization data
    const atlasSwapSetup = new web3.eth.Contract(
      AtlasDexSwapSetup.abi,
      AtlasDexSwapSetup.address
    );
    const swapInitData = atlasSwapSetup.methods
      .setup(
        AtlasDexSwapImplementation.address,
        config.nativeWrappedAddress,
        config.feeCollector,
        config._1InchRouter,
        config._0xRouter
      )
      .encodeABI();

    // deploy conductor proxy
    await deployer.deploy(
      AtlasDexSwapProxy,
      AtlasDexSwapSetup.address,
      swapInitData
    );
  }
  console.log('---- ALL DEPLOYED ----');
  // deployer.deploy(AtlasDexSwap, config.nativeWrappedAddress, config.feeCollector);
};
