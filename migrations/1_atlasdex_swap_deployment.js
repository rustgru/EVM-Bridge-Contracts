var AtlasDexSwap = artifacts.require("./AtlasDexSwap.sol");

const _1inchRouter = '0x1111111254fb6c44bac0bed2854e76f90643097d';
const _OxRouter = '0xdef1c0ded9bec7f1a1670819833240f027b25eff';
module.exports = function(deployer) {
  deployer.deploy(AtlasDexSwap, _1inchRouter, _OxRouter);
};
