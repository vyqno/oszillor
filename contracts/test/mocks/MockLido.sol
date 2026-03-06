// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockLido
/// @notice Mock Lido stETH for testing VaultStrategy staking integration.
/// @dev On receive of WETH, mints 1:1 stETH (this contract IS the stETH token).
///      On receive of stETH (self-transfer), returns WETH 1:1.
contract MockLido {
    string public name = "Mock stETH";
    string public symbol = "stETH";
    uint8 public decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    IERC20 public immutable weth;

    constructor(address _weth) {
        weth = IERC20(_weth);
    }

    /// @dev When VaultStrategy transfers WETH to this contract, we mint stETH back.
    function transfer(address to, uint256 amount) external returns (bool) {
        if (msg.sender == address(this)) {
            // This is an unstake: burn stETH and return WETH
            // (Called via safeTransfer from strategy)
            balanceOf[to] -= amount;
            totalSupply -= amount;
            weth.transfer(to, amount);
        } else {
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount;

            // If receiving WETH from strategy → mint stETH 1:1
            if (to == address(this)) {
                // This is a stake: strategy sends WETH, we mint stETH
                balanceOf[msg.sender] += amount;
                totalSupply += amount;
            }
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (msg.sender != from) {
            allowance[from][msg.sender] -= amount;
        }
        balanceOf[from] -= amount;

        if (to == address(this)) {
            // Staking: strategy sends WETH via safeTransfer → mint stETH 1:1
            balanceOf[from] += amount;
            totalSupply += amount;
        } else {
            balanceOf[to] += amount;
        }
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    // Mint helper for tests
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }
}
