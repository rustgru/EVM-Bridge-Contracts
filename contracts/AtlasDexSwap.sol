// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract WormholeStructs {
    struct Transfer {
        // PayloadID uint8 = 1
        uint8 payloadID;
        // Amount being transferred (big-endian uint256)
        uint256 amount;
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
        // Chain ID of the token
        uint16 tokenChain;
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes
        bytes32 to;
        // Chain ID of the recipient
        uint16 toChain;
        // Amount of tokens (big-endian uint256) that the user is willing to pay as relayer fee. Must be <= Amount.
        uint256 fee;
    }

	struct Signature {
		bytes32 r;
		bytes32 s;
		uint8 v;
		uint8 guardianIndex;
	}

	struct VM {
		uint8 version;
		uint32 timestamp;
		uint32 nonce;
		uint16 emitterChainId;
		bytes32 emitterAddress;
		uint64 sequence;
		uint8 consistencyLevel;
		bytes payload;

		uint32 guardianSetIndex;
		Signature[] signatures;

		bytes32 hash;
	}
    struct AssetMeta {
        // PayloadID uint8 = 2
        uint8 payloadID;
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
        // Chain ID of the token
        uint16 tokenChain;
        // Number of decimals of the token (big-endian uint256)
        uint8 decimals;
        // Symbol of the token (UTF-8)
        bytes32 symbol;
        // Name of the token (UTF-8)
        bytes32 name;
    }
}

/**
 * @title IWormhole
 * @dev Wormhole functions to call them for decoding/encoding VAA
 */
abstract contract IWormhole {
function parseAndVerifyVM(bytes calldata encodedVM) public virtual view returns (WormholeStructs.VM memory vm, bool valid, string memory reason);
}
/**
 * @title IBridgeWormhole
 * @dev Wormhole bridge functions to call them for swaping
 */
abstract contract IBridgeWormhole {
    function tokenImplementation() public view virtual returns (address);
    function chainId() public view virtual returns  (uint16);
    function wormhole() public view virtual returns  (address);
    function isTransferCompleted(bytes32 hash) public virtual view returns (bool);
    function completeTransfer(bytes memory encodedVm) public virtual;
    function parseTransfer(bytes memory encoded) public virtual pure returns (WormholeStructs.Transfer memory transfer);
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

    struct _0xSwapDescription {
        address inputToken;
        address outputToken;
        uint256 inputTokenAmount;
    }



    address public oneInchAggregatorRouter;
    address public OxAggregatorRouter;
    address public NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 MAX_INT = 2**256 - 1;

    event AmountLocked (address indexed dstReceiver, uint256 amountReceived);
    constructor(address _oneInchAggregatorRouter, address _OxAggregatorRouter) {
        oneInchAggregatorRouter = _oneInchAggregatorRouter;
        OxAggregatorRouter = _OxAggregatorRouter;
    }

    function test (bytes calldata data) external pure returns (address) {
         ( _0xSwapDescription memory swapDescriptionObj) = abi.decode(data[4:], (_0xSwapDescription));
        return address(swapDescriptionObj.inputToken);
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

    function approveSelfTokens (address erc20Address, address spender,  uint256 _approvalAmount) external onlyOwner {
        IERC20(erc20Address).safeApprove(spender, _approvalAmount);
    }
    
    /**
     * @dev Swap Tokens on 0x. 
     * @param _0xData a 0x data to call aggregate router to swap assets.
     */
    function _swapToken0x(bytes calldata _0xData) internal returns (bool) {

        ( _0xSwapDescription memory swapDescriptionObj) = abi.decode(_0xData[4:], (_0xSwapDescription));
        uint256 outputCurrencyBalanceBeforeSwap = 0;

        // this if else is to save output token balance
        if (address(swapDescriptionObj.outputToken) == NATIVE_ADDRESS) {
            outputCurrencyBalanceBeforeSwap = address(this).balance;
        } else {
            IERC20 swapOutputToken = IERC20(swapDescriptionObj.outputToken);
            outputCurrencyBalanceBeforeSwap = swapOutputToken.balanceOf(address(this));
        } // end of else

        
        if (address(swapDescriptionObj.inputToken) == NATIVE_ADDRESS) {
            // It means we are trying to transfer with Native amount
            require(msg.value >= swapDescriptionObj.inputTokenAmount, "Atlas DEX: Amount Not match with Swap Amount.");
        } else {
            IERC20 swapSrcToken = IERC20(swapDescriptionObj.inputToken);
            if (swapSrcToken.allowance(address(this), OxAggregatorRouter) < swapDescriptionObj.inputTokenAmount) {
                swapSrcToken.safeApprove(OxAggregatorRouter, MAX_INT);
            }

            require(swapSrcToken.balanceOf(msg.sender) >= swapDescriptionObj.inputTokenAmount, "Atlas DEX: You have insufficent balance to swap");
            swapSrcToken.safeTransferFrom(msg.sender, address(this), swapDescriptionObj.inputTokenAmount);
        }



        (bool success, ) = address(OxAggregatorRouter).call{ value: msg.value }(_0xData);
        require(success, "Atlas Dex: Swap Return Failed");
        // Again this check is to maintain for sending recieve balance to msg.sender
        if (address(swapDescriptionObj.outputToken) == NATIVE_ADDRESS) {
            uint256 outputCurrencyBalanceAfterSwap = address(this).balance ;
            outputCurrencyBalanceAfterSwap = outputCurrencyBalanceAfterSwap - outputCurrencyBalanceBeforeSwap;
            require(outputCurrencyBalanceAfterSwap > 0, "Atas DEX: Transfer output amount should be greater than 0.");
            payable(msg.sender).transfer(outputCurrencyBalanceAfterSwap);
        } else {
            IERC20 swapOutputToken = IERC20(swapDescriptionObj.outputToken);
            uint256 outputCurrencyBalanceAfterSwap = swapOutputToken.balanceOf(address(this));
            outputCurrencyBalanceAfterSwap = outputCurrencyBalanceAfterSwap - outputCurrencyBalanceBeforeSwap;
            require(outputCurrencyBalanceAfterSwap > 0, "Atas DEX: Transfer output amount should be greater than 0.");
            swapOutputToken.safeTransfer(msg.sender, outputCurrencyBalanceAfterSwap);

        } // end of else
        // Now need to transfer fund to destination address. 
        return true;
    } // end of swap function
    /**
     * @dev Swap Tokens on 1inch. 
     * @param _1inchData a 1inch data to call aggregate router to swap assets.
     */
    function _swapToken1Inch(bytes calldata _1inchData) internal returns (bool) {
        (, SwapDescription memory swapDescriptionObj,) = abi.decode(_1inchData[4:], (address, SwapDescription, bytes));

        uint256 amountForNative = 0;
        if (address(swapDescriptionObj.srcToken) == NATIVE_ADDRESS) {
            // It means we are trying to transfer with Native amount
            require(msg.value >= swapDescriptionObj.amount, "Atlas DEX: Amount Not match with Swap Amount.");
            amountForNative = swapDescriptionObj.amount;
        } else {
            IERC20 swapSrcToken = IERC20(swapDescriptionObj.srcToken);
            if (swapSrcToken.allowance(address(this), oneInchAggregatorRouter) < swapDescriptionObj.amount) {
                swapSrcToken.safeApprove(oneInchAggregatorRouter, MAX_INT);
            }

            require(swapSrcToken.balanceOf(msg.sender) >= swapDescriptionObj.amount, "Atlas DEX: You have insufficent balance to swap");
            swapSrcToken.safeTransferFrom(msg.sender, address(this), swapDescriptionObj.amount);
        }


        (bool success, ) = address(oneInchAggregatorRouter).call{ value: amountForNative }(_1inchData);
        require(success, "Atlas Dex: Swap Return Failed");

        return true;
    } // end of swap function
    /**
     * @dev Swap Tokens on Chain. 
     * @param _1inchData a 1inch data to call aggregate router to swap assets.
     */
    function swapTokens(bytes calldata _1inchData, bytes calldata _0xData) external payable returns (bool) {
        if(_1inchData.length > 1) {
            return _swapToken1Inch(_1inchData);
        } else {
            return _swapToken0x(_0xData);
        }

    }

    /**
     * @dev Initate a wormhole bridge redeem call to unlock asset and then call 1inch router to swap tokens with unlocked balance.
     * @param _wormholeBridgeToken  a wormhole bridge where fromw need to redeem token
     * @param _encodedVAA  VAA for redeeming to get from wormhole guardians
     * @param _1inchData a 1inch data to call aggregate router to swap assets.
     */
    function redeemTokens(address _wormholeBridgeToken, bytes memory _encodedVAA,  bytes calldata _1inchData) external returns (bool) {
        // initiate wormhole bridge contract        
        IBridgeWormhole wormholeTokenBridgeContract =  IBridgeWormhole(_wormholeBridgeToken);

        // initiate wormhole contract        
        IWormhole wormholeContract = IWormhole(wormholeTokenBridgeContract.wormhole());

        (WormholeStructs.VM memory vm, ,) = wormholeContract.parseAndVerifyVM(_encodedVAA);

        WormholeStructs.Transfer memory transfer = wormholeTokenBridgeContract.parseTransfer(vm.payload);
        IERC20 transferToken = IERC20(address(uint160(uint256(transfer.tokenAddress))));

        wormholeTokenBridgeContract.completeTransfer(_encodedVAA);


        if(_1inchData.length == 1) {
            return true;
        }
        (, SwapDescription memory swapDescriptionObj,) = abi.decode(_1inchData[4:], (address, SwapDescription, bytes));


        // query decimals
        (,bytes memory queriedDecimals) = address(transferToken).staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));
        uint256 transferAmount = transfer.amount;

         if (decimals > 8) {
            transferAmount *= 10 ** (decimals - 8);
        }

        require(swapDescriptionObj.amount == transferAmount, "Atlas DEX: Amount Not match with Redeem Amount.");
        require(swapDescriptionObj.srcToken == transferToken, "Atlas DEX: Token Not Matched");


        transferToken.safeTransferFrom(msg.sender, address(this), transferAmount);
        if (swapDescriptionObj.srcToken.allowance(address(this), oneInchAggregatorRouter) < swapDescriptionObj.amount) {
            swapDescriptionObj.srcToken.safeApprove(oneInchAggregatorRouter, MAX_INT);
        }
        (bool success,) = address(oneInchAggregatorRouter).call(_1inchData);
        if (!success) {
            revert();
        }

        return true;

    } // end of redeem Token
        
    /**
     * @dev Initiate a 1inch router to swap tokens and then wormhole bridge call to lock asset.
     * @param _wormholeBridgeToken  a wormhole bridge where need to lock token
     * @param _1inchData a 1inch data to call aggregate router to swap assets.
     */
    function lockedTokens(address _wormholeBridgeToken, address _wormholeToken, uint256 _amount, 
        uint16 _recipientChain, bytes32 _recipient, uint32 _nonce,  bytes calldata _1inchData) external payable returns (uint64) {
        // initiate wormhole bridge contract        
        IBridgeWormhole wormholeTokenBridgeContract =  IBridgeWormhole(_wormholeBridgeToken);
        IERC20 wormholeWrappedToken = IERC20(_wormholeToken);
        uint256 amountToLock = _amount; 
        if(_1inchData.length > 1) { // it means user need to first convert token to wormhole token.
            (, SwapDescription memory swapDescriptionObj,) = abi.decode(_1inchData[4:], (address, SwapDescription, bytes));


            require(swapDescriptionObj.dstToken == wormholeWrappedToken, "Atlas DEX: Dest Token Not Matched");

            uint256 amountForNative = 0;
            if (address(swapDescriptionObj.srcToken) == NATIVE_ADDRESS) {
                // It means we are trying to transfer with Native amount
                require(msg.value >= swapDescriptionObj.amount, "Atlas DEX: Amount Not match with Swap Amount.");
                amountForNative = swapDescriptionObj.amount;
            } else {
                IERC20 swapSrcToken = IERC20(swapDescriptionObj.srcToken);
                
                
                require(swapSrcToken.balanceOf(msg.sender) >= swapDescriptionObj.amount, "Atlas DEX: You have insufficient balance to swap");
                swapSrcToken.safeTransferFrom(msg.sender, address(this), swapDescriptionObj.amount);

                if (swapSrcToken.allowance(address(this), oneInchAggregatorRouter) < swapDescriptionObj.amount) {
                    swapSrcToken.safeApprove(oneInchAggregatorRouter, MAX_INT);
                }

            }


            (bool success, bytes memory _returnData) = address(oneInchAggregatorRouter).call{ value: amountForNative }(_1inchData);
            require(success, "Atlas Dex: Swap Return Failed");

            (uint returnAmount, ) = abi.decode(_returnData, (uint, uint));
            amountToLock = returnAmount;

        } // end of if for 1 inch data. 



        require(wormholeWrappedToken.balanceOf(msg.sender) >= amountToLock, "Atlas DEX: You have low balance to lock.");

        wormholeWrappedToken.safeTransferFrom(msg.sender, address(this), amountToLock);

        if (wormholeWrappedToken.allowance(address(this), _wormholeBridgeToken) < amountToLock) {
            wormholeWrappedToken.safeApprove(_wormholeBridgeToken, MAX_INT);
        }
        emit AmountLocked(msg.sender, amountToLock);
        uint64 sequence = wormholeTokenBridgeContract.transferTokens(_wormholeToken, amountToLock, _recipientChain, _recipient, 0, _nonce);
        return sequence;

    } // end of redeem Token

    receive() external payable {}

} // end of class