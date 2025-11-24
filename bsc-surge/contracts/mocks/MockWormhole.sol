// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../IWormholeCore.sol";

contract MockWormhole is IWormholeCore {
    uint256 public fee = 1000;
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
        vm = abi.decode(encodedVm, (VM));
        valid = true;
        reason = "";
    }
}
