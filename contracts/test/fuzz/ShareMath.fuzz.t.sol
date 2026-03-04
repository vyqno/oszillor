// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";

/// @title ShareMathFuzzTest
/// @author Hitesh (vyqno)
/// @notice Stateless fuzz tests for ShareMath conversion functions.
contract ShareMathFuzzTest is Test {
    /// @notice Vault-based round-trip: amount -> shares -> amount has negligible loss.
    /// @dev Virtual offset + floor rounding on both conversions can accumulate
    ///      multi-wei error at extreme share/asset ratios. This is by design:
    ///      rounding always favors the protocol (depositors never get more than they put in).
    function testFuzz_amountToShares_roundTrip(
        uint256 amount,
        uint256 totalShares,
        uint256 totalAssets
    ) public pure {
        amount = bound(amount, 1e6, 1e15);          // 1 USDC to 1B USDC
        totalAssets = bound(totalAssets, 0, 1e15);   // up to 1B USDC
        // Share price must be in realistic range: totalShares ≈ totalAssets (within 100x)
        // This reflects a vault where rebaseIndex stays within [MIN, MAX]
        uint256 minShares = totalAssets > 0 ? totalAssets / 100 : 0;
        uint256 maxShares = totalAssets > 0 ? totalAssets * 100 : 1e15;
        totalShares = bound(totalShares, minShares, maxShares);

        uint256 shares = ShareMath.amountToShares(amount, totalShares, totalAssets);
        uint256 recovered = ShareMath.sharesToAmount(shares, totalShares + shares, totalAssets + amount);

        // Recovered must be <= deposit (protocol-favored rounding)
        assertLe(recovered, amount, "Protocol must never overpay on round-trip");
        // Rounding loss must be negligible (< 0.001% or 100 wei, whichever is larger)
        uint256 maxDelta = amount / 100_000;
        if (maxDelta < 100) maxDelta = 100;
        assertApproxEqAbs(recovered, amount, maxDelta, "Round-trip loss must be negligible");
    }

    /// @notice Index-based round-trip: amount -> shares -> amount has negligible loss.
    /// @dev At extreme indices (near MIN_REBASE_INDEX), very large share counts
    ///      cause multi-wei floor rounding. Proportional error stays negligible.
    function testFuzz_indexRoundTrip(uint256 amount, uint256 rebaseIndex) public pure {
        amount = bound(amount, 1e6, 1e15);
        rebaseIndex = bound(rebaseIndex, RiskMath.MIN_REBASE_INDEX, RiskMath.MAX_REBASE_INDEX);

        uint256 shares = ShareMath.amountToSharesByIndex(amount, rebaseIndex);
        uint256 recovered = ShareMath.sharesToAmountByIndex(shares, rebaseIndex);

        // Recovered must be <= original (floor rounding is protocol-favored)
        assertLe(recovered, amount, "Protocol must never overpay on index round-trip");
        // Proportional tolerance: < 0.001% or 100 wei
        uint256 maxDelta = amount / 100_000;
        if (maxDelta < 100) maxDelta = 100;
        assertApproxEqAbs(recovered, amount, maxDelta, "Index round-trip loss must be negligible");
    }

    /// @notice First depositor always gets > 0 shares (CRIT-01).
    function testFuzz_firstDeposit_alwaysGetsShares(uint256 amount) public pure {
        amount = bound(amount, 1, type(uint96).max);

        uint256 shares = ShareMath.amountToShares(amount, 0, 0);
        assertGt(shares, 0, "First deposit must always produce shares");
    }

    /// @notice Shares should scale monotonically with amount.
    function testFuzz_sharesScaleLinearly(uint256 amount1, uint256 amount2) public pure {
        amount1 = bound(amount1, 1e6, type(uint64).max);
        amount2 = bound(amount2, 1e6, type(uint64).max);

        uint256 totalShares = 10_000_000;
        uint256 totalAssets = 10_000_000;

        uint256 shares1 = ShareMath.amountToShares(amount1, totalShares, totalAssets);
        uint256 shares2 = ShareMath.amountToShares(amount2, totalShares, totalAssets);

        if (amount1 >= amount2) {
            assertGe(shares1, shares2, "More assets should produce more or equal shares");
        } else {
            assertLe(shares1, shares2, "Fewer assets should produce fewer or equal shares");
        }
    }

    /// @notice At rebaseIndex = 1e18, shares == amounts (identity conversion).
    function testFuzz_indexAtPrecision_sharesEqualAmounts(uint256 amount) public pure {
        amount = bound(amount, 0, type(uint128).max);

        uint256 shares = ShareMath.amountToSharesByIndex(amount, 1e18);
        assertEq(shares, amount, "At 1e18 index, shares should equal amounts");
    }
}
