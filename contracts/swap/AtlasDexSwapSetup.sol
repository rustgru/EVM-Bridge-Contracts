// contracts/BridgeSetup.sol
// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";

contract AtlasDexSwapSetup is ERC1967Upgrade {
    function setup(
        address implementation
    ) public {
        _upgradeTo(implementation);
    }
}
