// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";

/// @title MockUniswapRouter
/// @notice Mock Uniswap V3 SwapRouter for testing VaultStrategy swaps.
/// @dev Simulates exact-input swaps at a configurable exchange rate.
///      Rate is expressed as USDC per ETH (e.g., 3000e6 = $3000/ETH).
contract MockUniswapRouter {
    uint256 public ethUsdRate; // USDC per 1 WETH (6 decimal USDC units per 1e18 WETH)
    address public weth;
    address public usdc;

    constructor(uint256 initialRate) {
        ethUsdRate = initialRate; // e.g., 3000e6 for $3000/ETH
    }

    /// @dev Must be called after deployment to set token addresses.
    function setTokens(address _weth, address _usdc) external {
        weth = _weth;
        usdc = _usdc;
    }

    function exactInputSingle(ISwapRouter.ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        // Pull input tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Calculate output based on mock rate using explicit token comparison
        if (params.tokenIn == weth && params.tokenOut == usdc) {
            // WETH → USDC
            // amountOut (6 dec) = amountIn (18 dec) * rate (6 dec) / 1e18
            amountOut = (params.amountIn * ethUsdRate) / 1e18;
        } else if (params.tokenIn == usdc && params.tokenOut == weth) {
            // USDC → WETH
            // amountOut (18 dec) = amountIn (6 dec) * 1e18 / rate (6 dec)
            amountOut = (params.amountIn * 1e18) / ethUsdRate;
        } else {
            revert("MockRouter: unknown pair");
        }

        require(amountOut >= params.amountOutMinimum, "Too little received");

        // Send output tokens
        IERC20(params.tokenOut).transfer(msg.sender, amountOut);
    }

    // Test helpers
    function setRate(uint256 newRate) external {
        ethUsdRate = newRate;
    }
}
