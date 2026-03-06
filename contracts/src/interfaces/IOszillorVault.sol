// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {RiskLevel, RiskState, Allocation} from "../libraries/DataStructures.sol";

/// @title IOszillorVault
/// @author Hitesh (vyqno)
/// @notice Interface for the OSZILLOR stablecoin vault (ERC-4626 compatible).
/// @dev Tracks internal accounting via `internalTotalAssets` — never raw `balanceOf`
///      (CRIT-06 donation attack fix). Constructor sets all roles — no post-deploy
///      `setController()` (HIGH-04 fix). Risk state initializes to CAUTION (CRIT-03 fix).
interface IOszillorVault {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a user deposits stablecoins and receives shares.
    /// @param depositor Address of the depositing user.
    /// @param assets Amount of stablecoins deposited.
    /// @param shares Number of shares minted.
    event Deposit(address indexed depositor, uint256 assets, uint256 shares);

    /// @notice Emitted when a user withdraws stablecoins by burning shares.
    /// @param withdrawer Address of the withdrawing user.
    /// @param assets Amount of stablecoins returned.
    /// @param shares Number of shares burned.
    event Withdraw(address indexed withdrawer, uint256 assets, uint256 shares);

    /// @notice Emitted when the risk score is updated by the RiskEngine.
    /// @param newScore The updated risk score (0-100).
    /// @param confidence DON consensus confidence (0-100).
    /// @param reasoningHash keccak256 of the AI reasoning string.
    event RiskScoreUpdated(uint256 newScore, uint256 confidence, bytes32 reasoningHash);

    /// @notice Emitted when risk score crosses the CRITICAL threshold (MED-07 fix).
    /// @param score The new risk score.
    /// @param level The new risk level.
    event RiskScoreWarning(uint256 score, RiskLevel level);

    /// @notice Emitted when yield-source allocations are updated.
    /// @param totalAllocations Number of allocations in the new set.
    event AllocationUpdated(uint256 totalAllocations);

    /// @notice Emitted when a rebase is triggered through the vault.
    /// @param factor The rebase factor applied.
    /// @param newIndex The resulting rebase index.
    event RebaseTriggered(uint256 factor, uint256 newIndex);

    /// @notice Emitted when emergency de-risk mode is activated.
    /// @param reason Human-readable reason for the emergency.
    /// @param duration Duration in seconds before auto-expiry.
    /// @param expiry Timestamp when emergency mode auto-expires.
    event EmergencyDeRisk(string reason, uint256 duration, uint256 expiry);

    /// @notice Emitted when emergency mode expires automatically.
    /// @param timestamp Block timestamp of the expiration.
    event EmergencyExpired(uint256 timestamp);

    /// @notice Emitted when emergency mode is manually exited.
    /// @param caller Address that triggered the exit.
    /// @param timestamp Block timestamp of the exit.
    event EmergencyExited(address indexed caller, uint256 timestamp);

    // ──────────────────── Mutative ────────────────────

    /// @notice Deposits stablecoins and mints OSZ shares to the caller.
    /// @dev Reverts if emergency mode is active, amount is below MIN_DEPOSIT,
    ///      or risk state is stale. Uses CEI pattern.
    /// @param assets Amount of stablecoins to deposit (6 decimals for USDC).
    /// @return shares Number of OSZ shares minted.
    function deposit(uint256 assets) external returns (uint256 shares);

    /// @notice Burns OSZ shares and returns stablecoins to the caller.
    /// @dev Withdrawals are ALWAYS allowed, even during emergency mode.
    /// @param shares Number of shares to burn.
    /// @return assets Amount of stablecoins returned.
    function withdraw(uint256 shares) external returns (uint256 assets);

    /// @notice Updates the on-chain risk state from a validated CRE W1 report.
    /// @dev Callable only by RISK_MANAGER_ROLE. Subject to rate limiting,
    ///      confidence gating, and delta clamping (HIGH-05 fix).
    /// @param score New risk score (0-100).
    /// @param confidence DON consensus confidence (0-100).
    /// @param reasoningHash keccak256 of the AI reasoning output.
    function updateRiskScore(uint256 score, uint256 confidence, bytes32 reasoningHash) external;

    /// @notice Updates yield-source allocations from a validated CRE W1 report.
    /// @dev Callable only by RISK_MANAGER_ROLE. Allocation percentages must sum
    ///      to exactly 10000 bps.
    /// @param allocs Array of new allocations.
    function updateAllocations(Allocation[] calldata allocs) external;

    /// @notice Triggers a rebase on the underlying token via the vault.
    /// @dev Callable only by REBASE_EXECUTOR_ROLE. Factor validated against bounds.
    /// @param factor Multiplicative rebase factor (1e18 precision).
    function triggerRebase(uint256 factor) external;

    /// @notice Activates time-bounded emergency mode, blocking deposits.
    /// @dev Callable only by SENTINEL_ROLE. Duration capped at MAX_EMERGENCY_DURATION
    ///      (4 hours). Auto-expires (HIGH-06 fix).
    /// @param reason Human-readable reason for the emergency.
    /// @param duration Seconds the emergency should last.
    function emergencyDeRisk(string calldata reason, uint256 duration) external;

    /// @notice Manually exits emergency mode before auto-expiry.
    /// @dev Callable only by EMERGENCY_UNPAUSER_ROLE.
    function exitEmergencyMode() external;

    // ──────────────────── Strategy (v2) ────────────────────

    /// @notice Emitted when the vault triggers a portfolio rebalance.
    /// @param targetEthPct Target ETH allocation in bps.
    /// @param actualEthPct Resulting ETH allocation after rebalance.
    event Rebalanced(uint256 targetEthPct, uint256 actualEthPct);

    /// @notice Delegates to VaultStrategy to adjust the ETH/USDC ratio.
    /// @dev Callable only by REBASE_EXECUTOR_ROLE (CRE W3 via RebaseExecutor).
    /// @param targetEthPct Target ETH allocation in bps (10000 = 100%).
    function rebalance(uint256 targetEthPct) external;

    /// @notice Returns the total NAV of the vault in WETH terms.
    /// @dev Includes WETH held + stETH value + USDC converted via Chainlink.
    function totalNav() external view returns (uint256);

    // ──────────────────── View ────────────────────

    /// @notice Returns the current risk score (0-100).
    function currentRiskScore() external view returns (uint256);

    /// @notice Returns the full on-chain risk state struct.
    function riskState() external view returns (RiskState memory);

    /// @notice Returns total assets tracked via internal accounting (CRIT-06 fix).
    /// @dev Never uses `balanceOf(address(this))` — immune to donation attacks.
    function totalAssets() external view returns (uint256);

    /// @notice Returns the internally tracked total assets counter.
    function internalTotalAssets() external view returns (uint256);

    /// @notice Returns whether emergency mode is currently active.
    function emergencyMode() external view returns (bool);

    /// @notice Returns the current risk level tier (SAFE/CAUTION/DANGER/CRITICAL).
    function riskLevel() external view returns (RiskLevel);

    /// @notice Returns the current yield-source allocation set.
    function getAllocations() external view returns (Allocation[] memory);

    /// @notice ERC-4626 compatible: max deposit given current risk state (MED-09 fix).
    /// @dev Returns 0 if emergency mode or DANGER/CRITICAL risk tier.
    /// @param receiver The intended deposit receiver (unused but required by ERC-4626).
    function maxDeposit(address receiver) external view returns (uint256);

    /// @notice ERC-4626 compatible: max withdrawal for an account.
    /// @param owner The account to query.
    function maxWithdraw(address owner) external view returns (uint256);
}
