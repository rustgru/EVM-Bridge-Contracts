var AtlasDexFarm = artifacts.require("AtlasDexFarm");

const BSC_FARUKH_BAHI_REWARD_TOKEN = "0xb8b66ccfF15A7118aE01C4ca9E2dD241DD5289f6";
const BSC_TOKENS_PER_BLOCK = (1 * 10**18).toString(); // 1 Token per block
const BSC_START_PER_BLOCK = 17221922;
const BSC_END_PER_BLOCK = 17321922;
module.exports = function(deployer) {
  deployer.deploy(AtlasDexFarm,BSC_FARUKH_BAHI_REWARD_TOKEN, BSC_TOKENS_PER_BLOCK, BSC_START_PER_BLOCK, BSC_END_PER_BLOCK );
};
