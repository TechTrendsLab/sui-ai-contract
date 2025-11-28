// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Surge is ERC20, Ownable2Step {
    
    error OnlySurgeBridgeExecutor();

    address public surgeBridgeExecutor;
    event BridgeMint(address indexed to, uint256 amount);
    event BridgeBurn(address indexed from, uint256 amount);
    event SurgeBridgeExecutorUpdated(address indexed newSurgeBridgeExecutor);

    modifier onlySurgeBridgeExecutor() {
        if (msg.sender != surgeBridgeExecutor) {
            revert OnlySurgeBridgeExecutor();
        }
        _;
    }

    constructor(address initialOwner) ERC20("SurgeAI", "SGE") Ownable(initialOwner) {
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    function bridgeMint(address to, uint256 amount) external onlySurgeBridgeExecutor {
        _mint(to, amount);
        emit BridgeMint(to, amount);
    }

    function bridgeBurn(address from, uint256 amount) external onlySurgeBridgeExecutor {
        _burn(from, amount);
        emit BridgeBurn(from, amount);
    }

    function setSurgeBridgeExecutor(address newSurgeBridgeExecutor) external onlyOwner {
        surgeBridgeExecutor = newSurgeBridgeExecutor;
        emit SurgeBridgeExecutorUpdated(newSurgeBridgeExecutor);
    }
}
