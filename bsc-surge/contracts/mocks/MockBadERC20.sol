// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 模拟没有返回值的 ERC20 (类似 USDT 在某些链上的实现)
contract MockNoReturnToken {
    mapping(address => uint256) public balanceOf;

    constructor() {}

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    // 没有返回值
    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

// 模拟返回 false 的 ERC20
contract MockFalseReturnToken {
    mapping(address => uint256) public balanceOf;

    constructor() {}

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false; // 总是失败
    }
}

