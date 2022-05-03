// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "../libraries/external/BytesLib.sol";

contract WormholeStructs {
    struct Transfer {
        // PayloadID uint8 = 1
        uint8 payloadID;
        // Amount being transferred (big-endian uint256)
        uint256 amount;
        
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
        
        // Address of the destination token. Left-zero-padded if shorter than 32 bytes
        bytes32 destTokenAddress;

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
    function publishMessage( uint32 nonce, bytes memory payload, uint8 consistencyLevel ) public virtual payable returns (uint64 sequence);
    function verifyVM(WormholeStructs.VM memory vm) public virtual view returns (bool valid, string memory reason);
    function parseVM(bytes memory encodedVM) public virtual pure returns (WormholeStructs.VM memory vm);
}

/**
 * @title AtlasDexSwapPOC
 * @dev Proxy contract to swap first Native to Native Using wormhole messaging.
 * successful.
 */
contract AtlasDexSwapPOC is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using BytesLib for bytes;
    using SafeMath for uint256;

    // Info of each user for stake.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
    }

    // Info of each user that stakes tokens.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed token, address indexed user, uint256 amount);
    event Withdraw(address indexed token, address indexed user, uint256 amount);

    struct AtlasDexSwapTransfer {
        // PayloadID uint8 = 1
        uint8 payloadID;
        // Amount being transferred (big-endian uint256)
        uint256 amount;
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
                
        // Address of the destination token. Left-zero-padded if shorter than 32 bytes
        bytes32 destTokenAddress;

        // Chain ID of the token
        uint16 tokenChain;
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes
        bytes32 to;
        // Chain ID of the recipient
        uint16 toChain;
        // Amount of tokens (big-endian uint256) that the user is willing to pay as relayer fee. Must be <= Amount.
        uint256 fee;
    }


    // Mapping of consumed token transfers
    mapping(bytes32 => bool) completedTransfers;
    
    // Mapping of emitter contracts on other chains
    mapping(uint16 => bytes32) emitterImplementations;
    
    // Mapping of wrapped assets (chainID => nativeAddress => wrappedAddress)
    mapping(uint16 => mapping(bytes32 => address)) wrappedAssets;
    
    // Current Chain ID
    uint16 CHAIN_ID;

    IWormhole public WORMHOLE_CONTRACT;

    constructor(address _wormhole, uint16 _CHAIN_ID) {
        WORMHOLE_CONTRACT = IWormhole(_wormhole);
        CHAIN_ID = _CHAIN_ID;
    }

    // Deposit tokens for TOKEN rewards.
    function deposit(address token, uint256 _amount) external nonReentrant{
        UserInfo storage user = userInfo[token][msg.sender];

        if (_amount > 0) {
            SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        emit Deposit(token, msg.sender, _amount);
    }

    // Withdraw tokens.
    function withdraw(address _token, uint256 _amount) external nonReentrant{
        UserInfo storage user = userInfo[_token][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            SafeERC20.safeTransfer(IERC20(_token), msg.sender, _amount);
        }
        emit Withdraw(_token, msg.sender, _amount);
    }

    function setupEmitter(bytes32 emitterAddress, uint16 emitterChainId) external onlyOwner returns (bool) {
        emitterImplementations[emitterChainId] = emitterAddress;
        return true;
    }

    function setupWrappedAsset(uint16 tokenChainId, bytes32 tokenAddress, address wrappedAssetAddress) external onlyOwner returns (bool) {
        wrappedAssets[tokenChainId][tokenAddress] = wrappedAssetAddress;
        return true;
    }

    function addressToBytes32(address _toConvert) external pure returns (bytes32 _converted) {
        _converted = bytes32(uint256(uint160(_toConvert)));
    }
    /**
    * Lock Tokens
    */
    function lockStableToken(address token, address destToken,  uint256 amount, uint16 recipientChain, bytes32 recipient, uint32 nonce) public payable nonReentrant returns (uint64 sequence) {
        uint16 tokenChain = chainId();
        bytes32 tokenAddress = bytes32(uint256(uint160(token)));
        bytes32 destTokenAddress = bytes32(uint256(uint160(destToken)));
        
        uint256 normalizedAmount = lockTokensToContract(token, amount);
        AtlasDexSwapTransfer memory transfer = AtlasDexSwapTransfer({
            payloadID : 1,
            amount : normalizedAmount,
            tokenAddress : tokenAddress,
            destTokenAddress: destTokenAddress,
            tokenChain : tokenChain,
            to : recipient,
            toChain : recipientChain,
            fee : 0
        });
        sequence = logTransfer( transfer, nonce);
    } // END OF LOCKED_TOKEN

    function lockTokensToContract (address token, uint256 amount) internal returns (uint256 normalizedAmount) {
        // query tokens decimals
        (,bytes memory queriedDecimals) = token.staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // don't deposit dust that can not be bridged due to the decimal shift
        amount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals);

        // query own token balance before transfer
        (,bytes memory queriedBalanceBefore) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        uint256 balanceBefore = abi.decode(queriedBalanceBefore, (uint256));

        // transfer tokens
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);

        // query own token balance after transfer
        (,bytes memory queriedBalanceAfter) = token.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        uint256 balanceAfter = abi.decode(queriedBalanceAfter, (uint256));

        // correct amount for potential transfer fees
        amount = balanceAfter - balanceBefore;

        // normalize amounts decimals
        normalizedAmount = normalizeAmount(amount, decimals);

    }
    function logTransfer(AtlasDexSwapTransfer memory transfer, uint32 nonce) internal returns (uint64 sequence) {

        bytes memory encoded = encodeTransfer(transfer);

        sequence = WORMHOLE_CONTRACT.publishMessage{
            value : 0
        }(nonce, encoded, 5);
    }
    
    function encodeTransfer(AtlasDexSwapTransfer memory transfer) public pure returns (bytes memory encoded) {
        encoded = abi.encodePacked(
            transfer.payloadID,
            transfer.amount,
            transfer.tokenAddress,
            transfer.destTokenAddress,
            transfer.tokenChain,
            transfer.to,
            transfer.toChain,
            transfer.fee
        );
    }

    /**
    * Unlock Tokens
    */
    function unlockStableTokens(bytes memory encodedVm) external returns (bool) {
        (WormholeStructs.VM memory vm, bool valid, string memory reason) = WORMHOLE_CONTRACT.parseAndVerifyVM(encodedVm);

        require(valid, reason);
        
        require(verifyEmitterVM(vm), "invalid emitter");

        AtlasDexSwapTransfer memory transfer = parseTransfer(vm.payload);

        require(!isTransferCompleted(vm.hash), "transfer already completed");
        setTransferCompleted(vm.hash);

        require(transfer.toChain == chainId(), "invalid target chain");

        //: TODO instead of passing this address from source chain, we need to figure out better deal.
        address wrapped = address(uint160(uint256(transfer.destTokenAddress)));
        // wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
        require(wrapped != address(0), "no wrapper for this token created yet");

        IERC20 transferToken = IERC20(wrapped);
        // query decimals
        (,bytes memory queriedDecimals) = address(transferToken).staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // adjust decimals
        uint256 transferAmount = deNormalizeAmount(transfer.amount, decimals);

        address transferRecipient = address(uint160(uint256(transfer.to)));

        SafeERC20.safeTransfer(transferToken, transferRecipient, transferAmount);
        return true;
    }

    function parseTransfer(bytes memory encoded) public pure returns (AtlasDexSwapTransfer memory transfer) {
        uint index = 0;

        transfer.payloadID = encoded.toUint8(index);
        index += 1;

        require(transfer.payloadID == 1, "invalid Transfer");

        transfer.amount = encoded.toUint256(index);
        index += 32;

        transfer.tokenAddress = encoded.toBytes32(index);
        index += 32;

        transfer.destTokenAddress = encoded.toBytes32(index);
        index += 32;

        transfer.tokenChain = encoded.toUint16(index);
        index += 2;

        transfer.to = encoded.toBytes32(index);
        index += 32;

        transfer.toChain = encoded.toUint16(index);
        index += 2;

        transfer.fee = encoded.toUint256(index);
        index += 32;

        require(encoded.length == index, "invalid Transfer");
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



    receive() external payable {}

    function setTransferCompleted(bytes32 hash) internal {
        completedTransfers[hash] = true;
    }

    function isTransferCompleted(bytes32 hash) public view returns (bool) {
        return completedTransfers[hash];
    }

    // We Are doing this 4 so that we should handle all cross chain.
    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 4) {
            amount /= 10 ** (decimals - 4);
        }
        return amount;
    }

    function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
        if (decimals > 4) {
            amount *= 10 ** (decimals - 4);
        }
        return amount;
    }

    function verifyEmitterVM(WormholeStructs.VM memory vm) internal view returns (bool){
        if (emitterImplementations[vm.emitterChainId] == vm.emitterAddress) {
            return true;
        }

        return false;
    }

    function chainId() public view returns (uint16){
        return CHAIN_ID;
    }

    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) public view returns (address){
        return wrappedAssets[tokenChainId][tokenAddress];
    }
} // end of class