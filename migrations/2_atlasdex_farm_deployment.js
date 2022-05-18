var AtlasDexFarm = artifacts.require("AtlasDexFarm");

const BSC_FARUKH_BAHI_REWARD_TOKEN = "0xd2dD03595860e36432C185A61Dd8c63c76e80EdA";
const BSC_TOKENS_PER_BLOCK = (0.1 * 10**18).toString(); // 1 Token per block
const BSC_START_PER_BLOCK = 10662170;
const BSC_END_PER_BLOCK = 10682170;
module.exports = function(deployer) {
  // deployer.deploy(AtlasDexFarm,BSC_FARUKH_BAHI_REWARD_TOKEN, BSC_TOKENS_PER_BLOCK, BSC_START_PER_BLOCK, BSC_END_PER_BLOCK );
};
