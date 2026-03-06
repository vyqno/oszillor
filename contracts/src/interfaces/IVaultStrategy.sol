// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IVaultStrategy
/// @author Hitesh (vyqno)
/// @notice Interface for the OSZILLOR v2 vault strategy (Lido staking + Uniswap hedging).
/// @dev Implemented by VaultStrategy.sol. Only callable by STRATEGY_MANAGER_ROLE (the vault).
interface IVaultStrategy {
    /// @notice Deposits WETH into Lido for stETH staking yield.
    /// @param amount Amount of WETH to stake.
    function stakeEth(uint256 amount) external;

    /// @notice Withdraws stETH back to WETH.
    /// @param stEthAmount Amount of stETH to unstake.
    function unstakeEth(uint256 stEthAmount) external;

    /// @notice Swaps WETH → USDC via Uniswap V3 (hedge to stablecoin).
    /// @param ethAmount Amount of WETH to swap.
    function hedgeToStable(uint256 ethAmount) external;

    /// @notice Swaps USDC → WETH via Uniswap V3 (unhedge back to ETH).
    /// @param usdcAmount Amount of USDC to swap.
    function unhedge(uint256 usdcAmount) external;

    /// @notice Adjusts the ETH/USDC ratio to match the target allocation.
    /// @param targetEthPct Target ETH allocation in bps (10000 = 100% ETH, 0 = 100% USDC).
    function rebalance(uint256 targetEthPct) external;

    /// @notice Returns the total strategy value denominated in WETH.
    /// @return Total NAV in WETH (18 decimals), including WETH + stETH + USDC→ETH conversion.
    function totalValueInEth() external view returns (uint256);

    /// @notice Returns the ETH-denominated balance (WETH + stETH value).
    function ethBalance() external view returns (uint256);

    /// @notice Returns the USDC balance converted to ETH terms via Chainlink.
    function stableBalance() external view returns (uint256);

    /// @notice Returns the current ETH allocation in bps (10000 = 100% ETH).
    function currentEthPct() external view returns (uint256);
}
