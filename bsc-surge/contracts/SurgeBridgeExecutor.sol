// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./Surge.sol";
import "./IWormholeCore.sol";

contract SurgeBridgeExecutor is Ownable {
    error InvalidAmount();
    error InsufficientFee();
    error InvalidAddress();
    error MessageAlreadyConsumed(bytes32 hash);
    error UnknownEmitter(uint16 chainId, bytes32 emitter);
    error InvalidPayload();

    struct TransferPayload {
        uint8 payloadId;
        bytes32 sender;
        bytes32 recipient;
        uint256 amount;
        uint16 sourceChain;
        uint16 targetChain;
    }

    uint8 public constant PAYLOAD_ID_TRANSFER = 1;

    Surge public immutable surge;
    IWormholeCore public immutable wormhole;
    uint16 public immutable wormholeChainId;
    uint8 public immutable consistencyLevel;

    uint32 private _nextNonce;
    address public feeRecipient;
    uint256 public minFee;

    mapping(uint16 => bytes32) public trustedEmitters;
    mapping(bytes32 => bool) public consumedMessages;

    event TransferInitiated(
        address indexed sender,
        uint256 amount,
        uint16 indexed targetChain,
        bytes32 indexed targetAddress,
        uint64 sequence,
        uint256 feeTaken
    );
    event TransferCompleted(
        bytes32 indexed emitterAddress,
        uint16 indexed emitterChainId,
        address indexed recipient,
        uint256 amount,
        bytes32 vaaHash
    );
    event TrustedEmitterUpdated(uint16 indexed chainId, bytes32 emitter);
    event FeeConfigUpdated(address indexed recipient, uint256 minFee);

    constructor(
        address surgeToken,
        address wormholeCore,
        uint16 wormholeChain,
        uint8 finality,
        address initialOwner,
        address feeRecipient_,
        uint256 minFee_
    ) Ownable(initialOwner) {
        if (surgeToken == address(0) || wormholeCore == address(0) || feeRecipient_ == address(0)) {
            revert InvalidAddress();
        }
        surge = Surge(surgeToken);
        wormhole = IWormholeCore(wormholeCore);
        wormholeChainId = wormholeChain;
        consistencyLevel = finality;
        feeRecipient = feeRecipient_;
        minFee = minFee_;
    }

    receive() external payable {
        revert("direct deposits not allowed");
    }

    function nextNonce() external view returns (uint32) {
        return _nextNonce;
    }

    function initiateTransfer(uint256 amount, bytes32 targetAddress, uint16 targetChain)
        external
        payable
        returns (uint64 sequence)
    {
        if (amount == 0 || targetAddress == bytes32(0) || targetChain == wormholeChainId) {
            revert InvalidAmount();
        }

        uint256 messageFee = wormhole.messageFee();
        uint256 requiredFee = messageFee + minFee;

        if (msg.value < requiredFee) {
            revert InsufficientFee();
        }

        bool success = surge.transferFrom(msg.sender, address(this), amount);
        require(success, "transfer failed");


        if (minFee > 0) {
            (bool feeSuccess, ) = feeRecipient.call{value: minFee}("");
            require(feeSuccess, "fee transfer failed");
        }

        surge.bridgeBurn(address(this), amount);

        TransferPayload memory payload = TransferPayload({
            payloadId: PAYLOAD_ID_TRANSFER,
            sender: _toWormholeFormat(msg.sender),
            recipient: targetAddress,
            amount: amount, 
            sourceChain: wormholeChainId,
            targetChain: targetChain
        });

        bytes memory encodedPayload = abi.encodePacked(
            payload.payloadId,
            payload.sender,
            payload.recipient,
            payload.amount,
            payload.sourceChain,
            payload.targetChain
        );

        sequence = wormhole.publishMessage{value: messageFee}(_nextNonce, encodedPayload, consistencyLevel);
        _nextNonce += 1;
        
        emit TransferInitiated(msg.sender, amount, targetChain, targetAddress, sequence, minFee);
    }


    function completeTransfer(bytes calldata encodedVm) external {
        (IWormholeCore.VM memory vm, bool valid, string memory reason) = wormhole.parseAndVerifyVM(encodedVm);
        require(valid, reason);

        bytes32 trustedEmitter = trustedEmitters[vm.emitterChainId];
        if (trustedEmitter == bytes32(0) || trustedEmitter != vm.emitterAddress) {
            revert UnknownEmitter(vm.emitterChainId, vm.emitterAddress);
        }

        if (consumedMessages[vm.hash]) {
            revert MessageAlreadyConsumed(vm.hash);
        }
        consumedMessages[vm.hash] = true;

        TransferPayload memory payload = _decodeTransferPayload(vm.payload);
        
        if (
            payload.payloadId != PAYLOAD_ID_TRANSFER
                || payload.targetChain != wormholeChainId
                || payload.sourceChain != vm.emitterChainId
        ) {
            revert InvalidPayload();
        }

        if (payload.amount == 0) {
            revert InvalidAmount();
        }

        address recipient = _fromWormholeFormat(payload.recipient);
        surge.bridgeMint(recipient, payload.amount);

        emit TransferCompleted(vm.emitterAddress, vm.emitterChainId, recipient, payload.amount, vm.hash);
    }

    function _decodeTransferPayload(bytes memory data) public view returns (TransferPayload memory payload) {

        uint256 offset = 0;
        
        if (data.length < 101) {
             revert InvalidPayload();
        }

        payload.payloadId = uint8(data[offset]);
        offset += 1;

        bytes32 sender;
        assembly {
            sender := mload(add(add(data, 32), offset))
        }
        payload.sender = sender;
        offset += 32;

        bytes32 recipient;
        assembly {
            recipient := mload(add(add(data, 32), offset))
        }
        payload.recipient = recipient;
        offset += 32;

        uint256 amount;
        assembly {
            amount := mload(add(add(data, 32), offset))
        }
        payload.amount = amount;
        
        offset += 32;

        payload.sourceChain = uint16(uint8(data[offset])) << 8 | uint16(uint8(data[offset + 1]));
        offset += 2;

        payload.targetChain = uint16(uint8(data[offset])) << 8 | uint16(uint8(data[offset + 1]));
        offset += 2;
    }


    function setTrustedEmitter(uint16 chainId, bytes32 emitter) external onlyOwner {
        if (chainId == 0 || emitter == bytes32(0)) {
            revert InvalidAddress();
        }
        trustedEmitters[chainId] = emitter;
        emit TrustedEmitterUpdated(chainId, emitter);
    }

    function updateFeeConfig(address newRecipient, uint256 newMinFee) external onlyOwner {
        if (newRecipient == address(0)) {
            revert InvalidAddress();
        }
        feeRecipient = newRecipient;
        minFee = newMinFee;
        emit FeeConfigUpdated(newRecipient, newMinFee);
    }

    function rescueNative(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert InvalidAddress();
        }
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "native transfer failed");
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0) || to == address(0)) {
            revert InvalidAddress();
        }
        bool ok = IERC20(token).transfer(to, amount);
        require(ok, "erc20 rescue failed");
    }

    function _toWormholeFormat(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    function _fromWormholeFormat(bytes32 data) internal pure returns (address) {
        if (uint256(data) >> 160 != 0) {
            revert InvalidAddress();
        }
        return address(uint160(uint256(data)));
    }
}
