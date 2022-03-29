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
    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) public view virtual returns (address);
    function tokenImplementation() public view virtual returns (address);
    function chainId() public view virtual returns  (uint16);
    function wormhole() public view virtual returns  (address);
    function isTransferCompleted(bytes32 hash) public virtual view returns (bool);
    function completeTransfer(bytes memory encodedVm) public virtual;
    function parseTransfer(bytes memory encoded) public virtual pure returns (WormholeStructs.Transfer memory transfer);
    function transferTokens(address token, uint256 amount, uint16 recipientChain, bytes32 recipient, uint256 arbiterFee, uint32 nonce) public virtual payable returns (uint64 sequence) ;
}

// A partial WETH interfaec.
interface IWETH is IERC20 {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

/**
 * @title AtlasDexSwap
 * @dev Proxy contract to swap first by redeeming from wormhole and then call 1inch router to swap assets
 * successful.
 */
contract AtlasDexSwap is Ownable {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

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
    address public NATIVE_WRAPPED_ADDRESS = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // bsc address
    uint256 MAX_INT = 2**256 - 1;
    uint256 public FEE_PERCENT = 15; // we will use 15
    uint256 public FEE_PERCENT_DENOMINATOR = 10000; // 
    address public FEE_COLLECTOR;
    event AmountLocked (address indexed dstReceiver, uint256 amountReceived);
    constructor(address nativeWrappedAddress, address _feeCollector) {
        require(nativeWrappedAddress != address(0), "Atlas Dex: Invalid Wrapped address");
        require(_feeCollector != address(0), "Atlas Dex: Fee Collector Invalid");         
        FEE_COLLECTOR = _feeCollector;
        NATIVE_WRAPPED_ADDRESS = nativeWrappedAddress;
        oneInchAggregatorRouter = 0x1111111254fb6c44bAC0beD2854e76F90643097d;
        OxAggregatorRouter = 0xDef1C0ded9bec7F1a1670819833240f027b25EfF;
    }
    
    function updateFeeCollector(address _feeCollector) external onlyOwner {
        require(_feeCollector != address(0), "Atlas Dex: Fee Collector Invalid");         
        FEE_COLLECTOR = _feeCollector;
    }

    function updateFeePercent(uint256 _feePercent) external onlyOwner {
        FEE_PERCENT = _feePercent;
    }
    
    function withdrawIfAnyEthBalance(address payable receiver) external onlyOwner returns (uint256) {
        uint256 balance = address(this).balance;
        receiver.transfer(balance);
        return balance;
    }
    
    function withdrawIfAnyTokenBalance(address contractAddress, address receiver) external onlyOwner returns (uint256) {
        IERC20 token = IERC20(contractAddress);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(receiver, balance);
        return balance;
    }

    function approveSelfTokens (address erc20Address, address spender,  uint256 _approvalAmount) external onlyOwner {
        IERC20(erc20Address).safeApprove(spender, _approvalAmount);
    }

    /**
     * @dev Withdraw Tokens on Wrapped. 
     */
    function withdrawToUnWrappedToken(uint256 _tokenAmount) internal returns (uint256) {
        IWETH wrapped = IWETH(NATIVE_WRAPPED_ADDRESS);
        require(wrapped.balanceOf(msg.sender) >= _tokenAmount, "Atlas DEX: You have insufficient balance to UnWrap");
        wrapped.safeTransferFrom(msg.sender, address(this), _tokenAmount);
        wrapped.withdraw(_tokenAmount);
        // First Calculating here deduct 0.15 percent.
        uint256 feeDeductionAmount = (_tokenAmount * FEE_PERCENT) / FEE_PERCENT_DENOMINATOR;
        payable(FEE_COLLECTOR).transfer(feeDeductionAmount);
        payable(msg.sender).transfer((_tokenAmount - feeDeductionAmount));
        return  _tokenAmount;
    } // end of deposit ToWrappedToken.    
    /**
     * @dev Deposit Tokens on Wrapped. 
     */
    function depositToWrappedToken() internal returns (uint256) {
        require(msg.value > 0, "Atlas Dex: Amount should be greater than 0 to deposit for wrapped.");
        IWETH wrapped = IWETH(NATIVE_WRAPPED_ADDRESS);
        wrapped.deposit{value: msg.value}();
        // First Calculating here deduct 0.15 percent.
        uint256 feeDeductionAmount = (msg.value * FEE_PERCENT) / FEE_PERCENT_DENOMINATOR;
        wrapped.transfer(FEE_COLLECTOR, feeDeductionAmount);

        wrapped.transfer(msg.sender, (msg.value - feeDeductionAmount));
        return  msg.value - feeDeductionAmount;
    } // end of deposit ToWrappedToken.
    /**
     * @dev Swap Tokens on 0x. 
     * @param _0xData a 0x data to call aggregate router to swap assets.
     */
    function _swapToken0x(bytes calldata _0xData) internal returns (uint256) {

        ( _0xSwapDescription memory swapDescriptionObj) = abi.decode(_0xData[4:], (_0xSwapDescription));
         if (swapDescriptionObj.inputToken == 0x0000000000000000000000000000000000000080) { // this is because as sometime 0x send data like sellToPancakeSwap or sellToUniswapSwap
                ( address[] memory tokens, uint256 sellAmount,, ) = abi.decode(_0xData[4:], (address[], uint256, uint256, uint8));
                swapDescriptionObj.inputToken = tokens[0];
                swapDescriptionObj.outputToken = tokens[tokens.length - 1];
                swapDescriptionObj.inputTokenAmount = sellAmount;
        }
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
        uint256 outputCurrencyBalanceAfterSwap = 0;
        // Again this check is to maintain for sending receiver balance to msg.sender
        if (address(swapDescriptionObj.outputToken) == NATIVE_ADDRESS) {
            outputCurrencyBalanceAfterSwap = address(this).balance ;
            outputCurrencyBalanceAfterSwap = outputCurrencyBalanceAfterSwap - outputCurrencyBalanceBeforeSwap;
            require(outputCurrencyBalanceAfterSwap > 0, "Atlas DEX: Transfer output amount should be greater than 0.");
            payable(msg.sender).transfer(outputCurrencyBalanceAfterSwap);
        } else {
            IERC20 swapOutputToken = IERC20(swapDescriptionObj.outputToken);
            outputCurrencyBalanceAfterSwap = swapOutputToken.balanceOf(address(this));
            outputCurrencyBalanceAfterSwap = outputCurrencyBalanceAfterSwap - outputCurrencyBalanceBeforeSwap;
            require(outputCurrencyBalanceAfterSwap > 0, "Atlas DEX: Transfer output amount should be greater than 0.");
            swapOutputToken.safeTransfer(msg.sender, outputCurrencyBalanceAfterSwap);
        } // end of else
        // Now need to transfer fund to destination address. 
        return outputCurrencyBalanceAfterSwap;
    } // end of swap function
    /**
     * @dev Swap Tokens on 1inch. 
     * @param _1inchData a 1inch data to call aggregate router to swap assets.
     */
    function _swapToken1Inch(bytes calldata _1inchData) internal returns (uint256) {
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

            require(swapSrcToken.balanceOf(msg.sender) >= swapDescriptionObj.amount, "Atlas DEX: You have insufficient balance to swap");
            swapSrcToken.safeTransferFrom(msg.sender, address(this), swapDescriptionObj.amount);
        }


        (bool success, bytes memory _returnData ) = address(oneInchAggregatorRouter).call{ value: amountForNative }(_1inchData);
        require(success, "Atlas Dex: Swap Return Failed");


        (uint returnAmount, ) = abi.decode(_returnData, (uint, uint));
        return returnAmount;
    } // end of swap function

    /**
     * @dev Swap Tokens on Chain. 
     * @param _1inchData a 1inch data to call aggregate router to swap assets.
     */
    function swapTokens(bytes calldata _1inchData, bytes calldata _0xData, bool _IsWrapped, bool _IsUnWrapped, uint256 _amount) external payable returns (uint256) {
        if(_1inchData.length > 1) {
            return _swapToken1Inch(_1inchData);
        } else if (_0xData.length > 1) {
            return _swapToken0x(_0xData);
        } else if (_IsWrapped) {
            return depositToWrappedToken();
        } else if ( _IsUnWrapped) {
            return withdrawToUnWrappedToken(_amount);
        }
        return 0;

    }

    /**
     * @dev Initiate a wormhole bridge redeem call to unlock asset and then call 1inch router to swap tokens with unlocked balance.
     * @param _wormholeTokenBridgeToken  a wormhole bridge where fromw need to redeem token
     * @param _encodedVAA  VAA for redeeming to get from wormhole guardians
     * @param _1inchData a 1inch data to call aggregate router to swap assets.
     * @param _0xData a 1inch data to call aggregate router to swap assets.
     */
    function unlockTokens(address _wormholeTokenBridgeToken, bytes memory _encodedVAA,  bytes calldata _1inchData, bytes calldata _0xData, bool _IsWrapped, bool _IsUnWrapped, uint256 _amount) external payable returns (uint256) {
        // initiate wormhole bridge contract  
        require(_wormholeTokenBridgeToken != address(0), "Atlas Dex: Wormhole Token Bride Address can't be null");      
        IBridgeWormhole wormholeTokenBridgeContract =  IBridgeWormhole(_wormholeTokenBridgeToken);

        // initiate wormhole contract        
        IWormhole wormholeContract = IWormhole(wormholeTokenBridgeContract.wormhole());

        (WormholeStructs.VM memory vm, ,) = wormholeContract.parseAndVerifyVM(_encodedVAA);

        WormholeStructs.Transfer memory transfer = wormholeTokenBridgeContract.parseTransfer(vm.payload);

        
        IERC20 transferToken;
        if (transfer.tokenChain == wormholeTokenBridgeContract.chainId()) {
            transferToken = IERC20(address(uint160(uint256(transfer.tokenAddress))));
        } else {
            address wrapped = wormholeTokenBridgeContract.wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
            require(wrapped != address(0), "AtlasDex: no wrapper for this token created yet");

            transferToken = IERC20(wrapped);
        }
        wormholeTokenBridgeContract.completeTransfer(_encodedVAA);


        uint256 amountTransfer;
        if(_1inchData.length > 1) {
            (, SwapDescription memory swapDescriptionObj,) = abi.decode(_1inchData[4:], (address, SwapDescription, bytes));
            require(swapDescriptionObj.srcToken == transferToken, "Atlas DEX: Token Not Matched");
            amountTransfer = _swapToken1Inch(_1inchData);
        } else if (_0xData.length > 1) {
            ( _0xSwapDescription memory swapDescriptionObj) = abi.decode(_0xData[4:], (_0xSwapDescription));
 

            if (swapDescriptionObj.inputToken == 0x0000000000000000000000000000000000000080) { // this is because as sometime 0x send data like sellToPancakeSwap or sellToUniswapSwap
                ( address[] memory tokens, uint256 sellAmount,, ) = abi.decode(_0xData[4:], (address[], uint256, uint256, uint8));
                swapDescriptionObj.inputToken = tokens[0];
                swapDescriptionObj.outputToken = tokens[tokens.length - 1];
                swapDescriptionObj.inputTokenAmount = sellAmount;
            }
            require(swapDescriptionObj.inputToken == address(transferToken), "Atlas DEX: Token Not Matched");

            amountTransfer = _swapToken0x(_0xData);
        }
        else if (_IsWrapped) {
            amountTransfer =  depositToWrappedToken();
        } else if ( _IsUnWrapped) {
            amountTransfer = withdrawToUnWrappedToken(_amount);
        }
        return amountTransfer;

    } // end of redeem Token

    struct LockedToken {
        address _wormholeBridgeToken;
        address _wormholeToken;
        uint256 _amount;
        uint16 _recipientChain;
        bytes32 _recipient;
        uint32 _nonce;
        bytes _1inchData;
        bytes _0xData;
        bool _IsWrapped;
        bool _IsUnWrapped;
        uint256 _amountToUnwrap;
    }
    /**
     * @dev Initiate a 1inch/_0x router to swap tokens and then wormhole bridge call to lock asset.
     * @param lockedTokenData  a wormhole bridge where need to lock token
     */
    function lockedTokens( LockedToken calldata lockedTokenData) external payable returns (uint64) {
        // initiate wormhole bridge contract        
        require(lockedTokenData._wormholeBridgeToken != address(0), "Atlas Dex: Wormhole Token Bride Address can't be null");      

        IBridgeWormhole wormholeTokenBridgeContract =  IBridgeWormhole(lockedTokenData._wormholeBridgeToken);
        IERC20 wormholeWrappedToken = IERC20(lockedTokenData._wormholeToken);
        uint256 amountToLock = lockedTokenData._amount; 
        if(lockedTokenData._1inchData.length > 1) { // it means user need to first convert token to wormhole token.
            (, SwapDescription memory swapDescriptionObj,) = abi.decode(lockedTokenData._1inchData[4:], (address, SwapDescription, bytes));
            require(swapDescriptionObj.dstToken == wormholeWrappedToken, "Atlas DEX: Dest Token Not Matched");        
            amountToLock = _swapToken1Inch(lockedTokenData._1inchData);
        } // end of if for 1 inch data. 
        else if(lockedTokenData._0xData.length > 1) { // it means user need to first convert token to wormhole token.
            ( _0xSwapDescription memory swapDescriptionObj) = abi.decode(lockedTokenData._0xData[4:], (_0xSwapDescription));
            if (swapDescriptionObj.inputToken == 0x0000000000000000000000000000000000000080) { // this is because as sometime 0x send data like sellToPancakeSwap or sellToUniswapSwap
                ( address[] memory tokens, uint256 sellAmount,, ) = abi.decode(lockedTokenData._0xData[4:], (address[], uint256, uint256, uint8));
                swapDescriptionObj.inputToken = tokens[0];
                swapDescriptionObj.outputToken = tokens[tokens.length - 1];
                swapDescriptionObj.inputTokenAmount = sellAmount;
            }
            require(swapDescriptionObj.outputToken == address(wormholeWrappedToken), "Atlas DEX: Dest Token Not Matched");        
            amountToLock = _swapToken0x(lockedTokenData._0xData);
        } // end of if for 1 inch data. 
        else if (lockedTokenData._IsWrapped) {
            amountToLock =  depositToWrappedToken();
        } else if ( lockedTokenData._IsUnWrapped) {
            amountToLock = withdrawToUnWrappedToken(lockedTokenData._amountToUnwrap);
        }


        require(wormholeWrappedToken.balanceOf(msg.sender) >= amountToLock, "Atlas DEX: You have low balance to lock.");

        wormholeWrappedToken.safeTransferFrom(msg.sender, address(this), amountToLock);

        // query tokens decimals
        (,bytes memory queriedDecimals) = address(wormholeWrappedToken).staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        uint256 amountForWormhole = deNormalizeAmount(normalizeAmount(amountToLock, decimals), decimals);

        if (wormholeWrappedToken.allowance(address(this), lockedTokenData._wormholeBridgeToken) < amountToLock) {
            wormholeWrappedToken.safeApprove(lockedTokenData._wormholeBridgeToken, MAX_INT);
        }
        emit AmountLocked(msg.sender, amountForWormhole);
        uint64 sequence = wormholeTokenBridgeContract.transferTokens(lockedTokenData._wormholeToken, amountForWormhole, lockedTokenData._recipientChain, lockedTokenData._recipient, 0, lockedTokenData._nonce);
        return sequence;

    } // end of redeem Token

    receive() external payable {}


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