// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ShareMath
/// @author Hitesh (vyqno)
/// @notice Pure share-to-amount conversion logic for the OSZILLOR protocol.
/// @dev Two conversion modes:
///      1. **Vault-based** (deposit/withdraw): uses totalShares and totalAssets with virtual offsets.
///      2. **Index-based** (balanceOf, transfers, bridging): uses rebaseIndex for O(1) rebases.
///
///      All arithmetic uses OZ Math.mulDiv for full 512-bit precision — prevents
///      division-before-multiplication truncation.
///
///      CRIT-01 fix: Virtual assets/shares permanently prevent the first-depositor
///      inflation attack. Even with zero real deposits, the virtual offset ensures
///      that share price cannot be manipulated via donation.
library ShareMath {
    /// @notice Virtual asset offset for inflation attack prevention (CRIT-01).
    /// @dev 1 virtual unit of the underlying asset.
    uint256 internal constant VIRTUAL_ASSETS = 1;

    /// @notice Virtual share offset for inflation attack prevention (CRIT-01).
    /// @dev 1M virtual shares create a large denominator, making share price
    ///      manipulation economically infeasible for the first depositor.
    uint256 internal constant VIRTUAL_SHARES = 1_000_000;

    /// @notice Converts an asset amount to shares using vault-level accounting.
    /// @param amount Asset amount to convert.
    /// @param totalShares Current total shares outstanding (excluding virtual).
    /// @param totalAssets Current total assets in the vault (excluding virtual).
    /// @return shares Number of shares the depositor would receive.
    function amountToShares(uint256 amount, uint256 totalShares, uint256 totalAssets)
        internal
        pure
        returns (uint256 shares)
    {
        shares = Math.mulDiv(
            amount,
            totalShares + VIRTUAL_SHARES,
            totalAssets + VIRTUAL_ASSETS,
            Math.Rounding.Floor
        );
    }

    /// @notice Converts shares to an asset amount using vault-level accounting.
    /// @param shares Number of shares to convert.
    /// @param totalShares Current total shares outstanding (excluding virtual).
    /// @param totalAssets Current total assets in the vault (excluding virtual).
    /// @return amount Asset amount the shares are worth.
    function sharesToAmount(uint256 shares, uint256 totalShares, uint256 totalAssets)
        internal
        pure
        returns (uint256 amount)
    {
        amount = Math.mulDiv(
            shares,
            totalAssets + VIRTUAL_ASSETS,
            totalShares + VIRTUAL_SHARES,
            Math.Rounding.Floor
        );
    }

    /// @notice Converts an asset amount to shares using the global rebase index.
    /// @dev Used by balanceOf, transfer, and bridging — O(1) rebase support.
    /// @param amount Asset amount to convert.
    /// @param rebaseIndex Current global rebase index (1e18 precision).
    /// @return shares Equivalent number of internal shares.
    function amountToSharesByIndex(uint256 amount, uint256 rebaseIndex)
        internal
        pure
        returns (uint256 shares)
    {
        shares = Math.mulDiv(amount, 1e18, rebaseIndex, Math.Rounding.Floor);
    }

    /// @notice Converts shares to an asset amount using the global rebase index.
    /// @dev Used by balanceOf — returns the user-facing "rebased" balance.
    /// @param shares Number of internal shares.
    /// @param rebaseIndex Current global rebase index (1e18 precision).
    /// @return amount User-facing asset-equivalent balance.
    function sharesToAmountByIndex(uint256 shares, uint256 rebaseIndex)
        internal
        pure
        returns (uint256 amount)
    {
        amount = Math.mulDiv(shares, rebaseIndex, 1e18, Math.Rounding.Floor);
    }
}
