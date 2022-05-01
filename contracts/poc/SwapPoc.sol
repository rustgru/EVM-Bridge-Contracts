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
    function publishMessage( uint32 nonce, bytes memory payload, uint8 consistencyLevel ) public virtual payable returns (uint64 sequence);
    function verifyVM(WormholeStructs.VM memory vm) public virtual view returns (bool valid, string memory reason);
    function parseVM(bytes memory encodedVM) public virtual pure returns (WormholeStructs.VM memory vm);
}

/**
 * @title AtlasDexSwapPOC
 * @dev Proxy contract to swap first Native to Native Using wormhole messaging.
 * successful.
 */
contract AtlasDexSwapPOC is Ownable {
    using SafeERC20 for IERC20;

    struct AtlasDexSwapTransfer {

        // Amount being transferred (big-endian uint256)
        uint256 amount;
        // Address of the token. Left-zero-padded if shorter than 32 bytes
        address tokenAddress;
        // Chain ID of the token
        uint16 tokenChain;
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes
        address to;
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
    mapping(uint16 => mapping(address => address)) wrappedAssets;
    
    // Current Chain ID
    uint16 CHAIN_ID;

    address public NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    IWormhole public WORMHOLE_CONTRACT;

    uint256 MAX_INT = 2**256 - 1;

    constructor(address _wormhole, uint16 _CHAIN_ID) {
        WORMHOLE_CONTRACT = IWormhole(_wormhole);
        CHAIN_ID = _CHAIN_ID;
    }

    function broadcastMessage ( uint32 nonce, bytes memory payload, uint8 consistencyLevel) external  payable returns (uint64 sequence){
        sequence = WORMHOLE_CONTRACT.publishMessage(nonce, payload, consistencyLevel);
    }
    function unlockStableTokens(bytes memory encodedVm) external returns (address) {
        (WormholeStructs.VM memory vm, bool valid, string memory reason) = WORMHOLE_CONTRACT.parseAndVerifyVM(encodedVm);

        require(valid, reason);
        
        require(verifyEmitterVM(vm), "invalid emitter");

        AtlasDexSwapTransfer memory transfer = abi.decode(vm.payload, (AtlasDexSwapTransfer));

        require(!isTransferCompleted(vm.hash), "transfer already completed");
        setTransferCompleted(vm.hash);

        require(transfer.toChain == chainId(), "invalid target chain");

        // require(wrapped != address(0), "no wrapper for this token created yet");

        address wrapped = wrappedAsset(transfer.tokenChain, transfer.tokenAddress);
        require(wrapped != address(0), "no wrapper for this token created yet");

        IERC20 transferToken = IERC20(wrapped);
        // query decimals
        (,bytes memory queriedDecimals) = address(transferToken).staticcall(abi.encodeWithSignature("decimals()"));
        uint8 decimals = abi.decode(queriedDecimals, (uint8));

        // adjust decimals
        uint256 transferAmount = deNormalizeAmount(transfer.amount, decimals);

        SafeERC20.safeTransfer(transferToken, transfer.to, transferAmount);
        return transfer.to;
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

    function verifyEmitterVM(WormholeStructs.VM memory vm) internal view returns (bool){
        if (emitterImplementations[vm.emitterChainId] == vm.emitterAddress) {
            return true;
        }

        return false;
    }

    function chainId() public view returns (uint16){
        return CHAIN_ID;
    }

    function wrappedAsset(uint16 tokenChainId, address tokenAddress) public view returns (address){
        return wrappedAssets[tokenChainId][tokenAddress];
    }
} // end of class