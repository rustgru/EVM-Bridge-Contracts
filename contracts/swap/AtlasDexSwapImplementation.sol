// contracts/Implementation.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

import "./AtlasDexSwap.sol";


contract AtlasDexSwapImplementation {
    // Beacon getter for the token contracts
    function implementation() public view returns (address) {
        return address(this);
    }

    function initialize() initializer public virtual {}

    modifier initializer() {
 /**
        address impl = ERC1967Upgrade._getImplementation();

        require(
            !isInitialized(impl),
            "already initialized"
        );
    */
        // setInitialized(impl);

        _;
    }
}
