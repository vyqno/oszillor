// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IOszillorToken
/// @author Hitesh (vyqno)
/// @notice Interface for the OSZILLOR rebase token (ERC-20 + ERC-677 + CCIP CCT).
/// @dev Share-based internal accounting: balanceOf(addr) = shares[addr] * rebaseIndex / 1e18.
///      Allowances are stored in shares, not amounts (HIGH-01 fix).
interface IOszillorToken {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted on every share movement alongside the standard ERC-20 Transfer event.
    /// @param from Sender address (address(0) for mints).
    /// @param to Recipient address (address(0) for burns).
    /// @param shares Number of internal shares transferred.
    event TransferShares(address indexed from, address indexed to, uint256 shares);

    /// @notice Emitted when a rebase is applied, changing the global rebaseIndex.
    /// @param epoch Monotonically increasing rebase counter.
    /// @param newIndex The new rebaseIndex after applying the factor.
    event Rebase(uint256 indexed epoch, uint256 newIndex);

    // ──────────────────── Mutative ────────────────────

    /// @notice Mints internal shares to a recipient. Does NOT move underlying assets.
    /// @dev Callable only by RISK_MANAGER_ROLE (vault).
    /// @param to Address receiving the minted shares.
    /// @param shares Number of shares to mint.
    function mintShares(address to, uint256 shares) external;

    /// @notice Burns internal shares from an account. Does NOT move underlying assets.
    /// @dev Callable only by RISK_MANAGER_ROLE (vault).
    /// @param from Address whose shares are burned.
    /// @param shares Number of shares to burn.
    function burnShares(address from, uint256 shares) external;

    /// @notice Applies a multiplicative rebase factor to the global rebaseIndex.
    /// @dev Callable only by REBASE_EXECUTOR_ROLE. Factor must be within
    ///      [MIN_REBASE_FACTOR, MAX_REBASE_FACTOR]. Index is clamped to
    ///      [MIN_REBASE_INDEX, MAX_REBASE_INDEX] (CRIT-02 fix).
    /// @param factor Multiplicative factor (1e18 precision). 1e18 = no change.
    /// @return newIndex The updated rebaseIndex after clamping.
    function rebase(uint256 factor) external returns (uint256 newIndex);

    // ──────────────────── View ────────────────────

    /// @notice Returns the internal share count for an account.
    /// @param account The address to query.
    /// @return The number of internal shares held.
    function sharesOf(address account) external view returns (uint256);

    /// @notice Returns the current global rebase index (1e18 precision).
    /// @return The rebaseIndex used to compute elastic balances.
    function rebaseIndex() external view returns (uint256);

    /// @notice Returns the total internal shares across all holders.
    /// @return The sum of all shares.
    function totalShares() external view returns (uint256);

    /// @notice Returns the timestamp of the last successful rebase.
    /// @return Unix timestamp.
    function lastRebaseTimestamp() external view returns (uint256);
}
