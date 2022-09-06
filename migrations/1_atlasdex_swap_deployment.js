var SwapImplementation = artifacts.require("SwapImplementation")
var SwapSetup = artifacts.require("SwapSetup");
var AtlasSwapProxy = artifacts.require("AtlasSwapProxy")
const DeploymentConfig = require(`${__dirname}/../deployment_config.js`);

module.exports = async function(deployer, network) {

  if (network === "ethereum-fork") {
    network = "ethereum";
  }
  const config = DeploymentConfig[network];
  console.log(network, '----')
  if (!config) {
    throw Error("deployment config undefined");
  }

  await deployer.deploy(SwapImplementation);

  if (!config.deployImplementationOnly) {
    // deploy conductor setup
    await deployer.deploy(SwapSetup);

    // encode initialization data
    const atlasSwapSetup = new web3.eth.Contract(
      SwapSetup.abi,
      SwapSetup.address
    );
    const swapInitData = atlasSwapSetup.methods
      .setup(
        SwapImplementation.address,
        config.nativeWrappedAddress,
        config.feeCollector,
        config._1InchRouter,
        config._0xRouter
      )
      .encodeABI();

    // deploy Swap proxy
    await deployer.deploy(
      AtlasSwapProxy,
      SwapSetup.address,
      swapInitData
    );
  } else {
    // initlaize Swap proxy with updated implementation address.
    const atlasSwapProxyContract = await SwapImplementation.at(AtlasSwapProxy.address);

    await atlasSwapProxyContract.upgrade.sendTransaction(SwapImplementation.address)
  }
  console.log('---- ALL DEPLOYED ----');
};
