// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../IWormholeCore.sol";

contract MockWormhole is IWormholeCore {
    uint256 public fee = 1000; // 默认一点费用
    uint64 public nextSequence = 0;

    function setMessageFee(uint256 _fee) external {
        fee = _fee;
    }

    function messageFee() external view override returns (uint256) {
        return fee;
    }

    function publishMessage(uint32 nonce, bytes memory payload, uint8 consistencyLevel)
        external
        payable
        override
        returns (uint64 sequence)
    {
        // 模拟检查费用
        require(msg.value >= fee, "Insufficient wormhole fee");
        sequence = nextSequence++;
        return sequence;
    }

    function parseAndVerifyVM(bytes calldata encodedVm)
        external
        view
        override
        returns (VM memory vm, bool valid, string memory reason)
    {
        // 这是一个 Mock，我们假设测试脚本会传递 ABI 编码的 VM 结构体
        // 这样我们就可以在测试中完全控制返回的 VM 数据
        vm = abi.decode(encodedVm, (VM));
        valid = true;
        reason = "";
    }
}

