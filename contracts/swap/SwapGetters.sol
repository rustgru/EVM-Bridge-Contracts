// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SwapState.sol";
import "./SwapStructs.sol";
import "../libraries/external/BytesLib.sol";

/**
 * @title AtlasDexSwap
 */
contract SwapGetters is SwapState {
    using BytesLib for bytes;

    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 8) {
            amount *= 10 ** (decimals - 8);
        }
        return amount;
    }

} // end of class