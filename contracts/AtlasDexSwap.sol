// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


/**
 * @title IBridgeWormhole
 * @dev Wormhole bridge functions to call them for swaping
 */
abstract contract IBridgeWormhole {
    function tokenImplementation() public view virtual returns (address);
    function chainId() public view virtual returns  (uint16);
    function completeTransfer(bytes memory encodedVm) public virtual;
    function transferTokens(address token, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce) public virtual payable returns (uint64 sequence) ;
}


/**
 * @title AtlasDexSwap
 * @dev Proxy contract to swap first by redeeming from wormhole and then call 1inch router to swap assets
 * successful.
 */
contract AtlasDexSwap is Ownable {
    using SafeERC20 for IERC20;

    struct SwapDescription {
        IERC20 srcToken;
        IERC20 dstToken;
        address srcReceiver;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    address public oneInchAggregatorRouter;
    address public OxAggregatorRouter;

    constructor(address _oneInchAggregatorRouter, address _OxAggregatorRouter) {
        oneInchAggregatorRouter = _oneInchAggregatorRouter;
        OxAggregatorRouter = _OxAggregatorRouter;
    }

    function update1inchAggregationRouter (address _newRouter) external onlyOwner returns (bool) {
        oneInchAggregatorRouter = _newRouter;
        return true;
    }

    function update0xAggregationRouter (address _newRouter) external onlyOwner returns (bool) {
        OxAggregatorRouter = _newRouter;
        return true;
    }
    
    function withdrawIfAnyEthBalance(address payable receiver) external onlyOwner returns (uint256) {
        uint256 balance = address(this).balance;
        receiver.transfer(balance);
        return balance;
    }
    
    function withdrawIfAnyTokenBalance(address contractAddress, address payable receiver) external onlyOwner returns (uint256) {
        IERC20 token = IERC20(contractAddress);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(receiver, balance);
        return balance;
    }


    
    /**
     * @dev Initate a wormhole bridge redeem call to unlock asset and then call 1inch router to swap tokens with unlocked balance.
     * @param _wormholeBridgeToken  a wormhole bridge where fromw need to redeem token
     * @param sourceToken is asset which we will be unlocking from wormhole bridge
     * @param _encodedVAA  VAA for redeeming to get from wormhole guardians
     * @param _data a 1inch data to call aggregate router to swap assets.
     */
    function redeemTokens(address _wormholeBridgeToken, address sourceToken, bytes calldata _encodedVAA,  bytes calldata _data) external {
        uint256 beforeRedeemBalance = IERC20(sourceToken).balanceOf(address(this));
        IBridgeWormhole wormholeTokenBridgeContract =  IBridgeWormhole(_wormholeBridgeToken);
        wormholeTokenBridgeContract.completeTransfer(_encodedVAA);
        
        uint256 afterRedeemBalance = IERC20(sourceToken).balanceOf(address(this));

        (address _c, SwapDescription memory swapDescriptionObj, bytes memory _d) = abi.decode(_data[4:], (address, SwapDescription, bytes));

        require(afterRedeemBalance > beforeRedeemBalance, "AtlasDex: No Balance Redeemed From Wormhole");
        require(swapDescriptionObj.amount == afterRedeemBalance - beforeRedeemBalance,  "AtlasDex: Swap amount not matched with redeemed balance");
        
        (bool success, bytes memory _returnData) = address(oneInchAggregatorRouter).call(_data);
        if (success) {
            (uint returnAmount, uint gasLeft) = abi.decode(_returnData, (uint, uint));
            // require(returnAmount >= minOut);
        } else {
            revert();
        }
    } // end of redeem Token

}