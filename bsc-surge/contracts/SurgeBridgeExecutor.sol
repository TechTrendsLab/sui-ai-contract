// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./Surge.sol";
import "./IWormholeCore.sol";

/**
 * @title SurgeBridgeExecutor
 * @notice 此合约负责在 Surge 代币与 Wormhole 跨链桥之间执行铸销、消息发送与验证的逻辑。
 * @dev 由链上唯一管理员负责配置信任发射器与费用参数，普通用户可以发起跨链燃烧请求。
 */
contract SurgeBridgeExecutor is Ownable {
    using SafeERC20 for IERC20;

    error InvalidAmount(); // 输入的数额非法（0 或计算后为空）
    error InsufficientFee(); // 手续费不足
    error InvalidAddress(); // 地址参数为空地址
    error MessageAlreadyConsumed(bytes32 hash); // VM 消息重复消费
    error UnknownEmitter(uint16 chainId, bytes32 emitter); // 来自未信任的链或发射器
    error InvalidPayload(); // 解码后的负载不符合预期

    struct TransferPayload {
        uint8 payloadId; // 负载类型，用于防止跨协议复用
        bytes32 sender; // Wormhole 格式的源地址
        bytes32 recipient; // Wormhole 格式的目标地址
        uint256 amount; // 转账金额（手续费扣除后）
        uint16 sourceChain; // 源链 ID
        uint16 targetChain; // 目标链 ID
    }

    uint8 public constant PAYLOAD_ID_TRANSFER = 1; // 唯一的跨链转账负载 ID
    // uint16 public constant MAX_BPS = 10_000; // 已弃用：不再使用 token 百分比手续费

    Surge public immutable surge; // Surge 代币合约
    IWormholeCore public immutable wormhole; // Wormhole 核心合约
    uint16 public immutable wormholeChainId; // 本链的 Wormhole Chain ID
    uint8 public immutable consistencyLevel; // 消息需要达到的最终性等级

    uint32 private _nextNonce; // 发送 Wormhole 消息的 nonce 递增计数
    address public feeRecipient; // 手续费接收地址
    uint256 public minFee; // 最小原生代币手续费

    mapping(uint16 => bytes32) public trustedEmitters; // 每条源链对应的信任发射器
    mapping(bytes32 => bool) public consumedMessages; // 已经处理过的 VM 哈希

    // 事件：用户发起跨链转账时记录关键参数，用于链下追踪
    event TransferInitiated(
        address indexed sender,
        uint256 amount,
        uint16 indexed targetChain,
        bytes32 indexed targetAddress,
        uint64 sequence,
        uint256 feeTaken
    );
    // 事件：跨链消息验证通过并铸币完成
    event TransferCompleted(
        bytes32 indexed emitterAddress,
        uint16 indexed emitterChainId,
        address indexed recipient,
        uint256 amount,
        bytes32 vaaHash
    );
    // 事件：更新信任发射器映射
    event TrustedEmitterUpdated(uint16 indexed chainId, bytes32 emitter);
    // 事件：更新手续费配置
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

    /// @notice 阻止直接向合约打入原生资产
    receive() external payable {
        revert("direct deposits not allowed"); // 不允许原生资产直接打入
    }

    /// @notice 查看下一个 Wormhole 消息的 nonce
    function nextNonce() external view returns (uint32) {
        return _nextNonce;
    }

    /// @notice 用户调用该函数发起跨链转账请求
    /// @param amount 用户希望跨链的 Surge 数量
    /// @param targetAddress 目标链上的 Wormhole 格式地址
    /// @param targetChain 目标链的 Wormhole Chain ID
    function initiateTransfer(uint256 amount, bytes32 targetAddress, uint16 targetChain)
        external
        payable
        returns (uint64 sequence)
    {
        if (amount == 0 || targetAddress == bytes32(0) || targetChain == wormholeChainId) {
            revert InvalidAmount();
        }

        uint256 messageFee = wormhole.messageFee(); // 查询 Wormhole 发送消息所需费用
        uint256 requiredFee = messageFee + minFee;

        if (msg.value < requiredFee) {
            revert InsufficientFee();
        }

        // Pull tokens from user
        bool success = surge.transferFrom(msg.sender, address(this), amount); // 从用户处转入 Surge 代币
        require(success, "transfer failed");


        if (minFee > 0) {
            (bool feeSuccess, ) = feeRecipient.call{value: minFee}("");
            require(feeSuccess, "fee transfer failed");
        }

        surge.bridgeBurn(address(this), amount); // 在当前链销毁代币，为目标链铸造做准备

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

        sequence = wormhole.publishMessage{value: messageFee}(_nextNonce, encodedPayload, consistencyLevel); // 发送跨链消息
        _nextNonce += 1; // 递增 nonce
        
        // // 退还多余的 ETH/BNB (扣除 Wormhole 费用和 minFee 后的剩余部分)
        // if (msg.value > messageFee) {
        //     (bool refundSuccess, ) = msg.sender.call{value: msg.value - messageFee}(""); // 退还多余 ETH
        //     require(refundSuccess, "refund failed");
        // }

        emit TransferInitiated(msg.sender, amount, targetChain, targetAddress, sequence, minFee);
    }


    /// @notice 鉴权并执行从 Wormhole 传入的跨链接收消息
    /// @param encodedVm Wormhole 验证后生成的 VAA 字节
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

        // 手动解析 Payload (支持 EVM 的 abi.encode 和其他链的 packed 格式)
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

    function _decodeTransferPayload(bytes memory data) public pure returns (TransferPayload memory payload) {

        // 手动解码 (Packed 格式)
        // 假设格式: [payloadId(1)][sender(32)][recipient(32)][amount(32)][sourceChain(2)][targetChain(2)]
        // 总长度: 1 + 32 + 32 + 32 + 2 + 2 = 101 字节
        // 注意：Sui/Move 端的 amount 可能是 8 字节，如果是 8 字节总长度为 77
        
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

        // Amount: 这里假设 Wormhole 标准是 32 字节大端序
        // 如果源链发的是 8 字节，需要根据实际长度调整
        uint256 amount;
        assembly {
            amount := mload(add(add(data, 32), offset))
        }
        payload.amount = amount;
        // 如果是 8 字节的情况，需要手动读取
        // uint64 amt64;
        // assembly { amt64 := mload(add(add(data, 8), offset)) } 这种写法不对，需要 shift
        
        offset += 32;

        // Source Chain (2 bytes)
        payload.sourceChain = uint16(uint8(data[offset])) << 8 | uint16(uint8(data[offset + 1]));
        offset += 2;

        // Target Chain (2 bytes)
        payload.targetChain = uint16(uint8(data[offset])) << 8 | uint16(uint8(data[offset + 1]));
        offset += 2;
    }


    /// @notice 设置某条链对应的信任发射器
    function setTrustedEmitter(uint16 chainId, bytes32 emitter) external onlyOwner {
        if (chainId == 0 || emitter == bytes32(0)) {
            revert InvalidAddress();
        }
        trustedEmitters[chainId] = emitter; // 为对应链配置新的发射器地址
        emit TrustedEmitterUpdated(chainId, emitter);
    }

    function removeTrustedEmitter(uint16 chainId) external onlyOwner {
        if (chainId == 0) {
            revert InvalidAddress();
        }
        trustedEmitters[chainId] = bytes32(0);
        emit TrustedEmitterUpdated(chainId, bytes32(0));
    }

    /// @notice 更新跨链手续费接收者及最低费用
    function updateFeeConfig(address newRecipient, uint256 newMinFee) external onlyOwner {
        if (newRecipient == address(0)) {
            revert InvalidAddress();
        }
        feeRecipient = newRecipient; // 更新手续费接收者
        minFee = newMinFee; // 更新最低手续费
        emit FeeConfigUpdated(newRecipient, newMinFee);
    }

    /// @notice 管理员提取合约内意外残留的原生代币
    function rescueNative(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) {
            revert InvalidAddress();
        }
        (bool sent, ) = to.call{value: amount}(""); // 赎回合约残留的原生资产
        require(sent, "native transfer failed");
    }

    /// @notice 管理员提取合约内遗留的其他 ERC20 资产
    function rescueERC20(address token, address to, uint256 amount) external onlyOwner {
        if (token == address(0) || to == address(0)) {
            revert InvalidAddress();
        }
        IERC20(token).safeTransfer(to, amount); // 提取其他 ERC20 资产，防止锁死
    }

    /// @dev 将 20 字节地址转换为 Wormhole 要求的 32 字节格式
    function _toWormholeFormat(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account))); // 将 EVM 地址左填充为 32 字节
    }

    /// @dev 将 Wormhole 32 字节地址还原为 EVM 地址
    function _fromWormholeFormat(bytes32 data) internal pure returns (address) {
        if (uint256(data) >> 160 != 0) {
            revert InvalidAddress();
        }
        return address(uint160(uint256(data))); // 仅保留低 20 字节恢复地址
    }
}

