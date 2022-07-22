// contracts/BridgeSetup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import "./SwapSetters.sol";
contract AtlasDexSwapSetup is SwapSetters, ERC1967Upgrade {
    function setup(
        address implementation,
        address nativeWrappedAddress, 
        address _feeCollector,
        address _1inchRouter,
        address _0xRouter
    ) public {

        setFeeCollector(_feeCollector);
        setNativeWrappedAddress(nativeWrappedAddress);
        set1InchRouter(_1inchRouter);
        set0xRouter(_0xRouter);
        _upgradeTo(implementation);
    }
}
