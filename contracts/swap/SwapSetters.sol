// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./SwapState.sol";
import "./SwapStructs.sol";

/**
 * @title SwapSetters
 */
contract SwapSetters is SwapState, AccessControl {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    using SafeMath for uint256;

    function updateFeeCollector(address _feeCollector) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not a admin");
        require(_feeCollector != address(0), "Atlas Dex: Fee Collector Invalid");         
        FEE_COLLECTOR = _feeCollector;
    }

    function updateFeePercent(uint256 _feePercent) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not a admin");
        require(_feePercent <= 3000, "Atlas Dex:  Fee can't be more than 0.3% on one side.");
        FEE_PERCENT = _feePercent;
    }
    
    function withdrawIfAnyEthBalance(address payable receiver) external returns (uint256) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not a admin");
        uint256 balance = address(this).balance;
        receiver.transfer(balance);
        return balance;
    }
    
    function withdrawIfAnyTokenBalance(address contractAddress, address receiver) external returns (uint256) {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Caller is not a admin");
        IERC20 token = IERC20(contractAddress);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(receiver, balance);
        return balance;
    }
} // end of class