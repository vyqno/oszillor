// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {RiskLevel} from "../../src/libraries/DataStructures.sol";

/// @title RiskMathFuzzTest
/// @author Hitesh (vyqno)
/// @notice Stateless fuzz tests for RiskMath — factor and index bounds safety.
contract RiskMathFuzzTest is Test {
    /// @notice calculateRebaseFactor always returns a value within [MIN, MAX].
    function testFuzz_factorAlwaysClamped(uint256 score, uint256 apyBps, uint256 timeDelta) public pure {
        score = bound(score, 0, 100);
        apyBps = bound(apyBps, 0, 3000); // max 30% APY
        timeDelta = bound(timeDelta, 0, 1 days);

        uint256 factor = RiskMath.calculateRebaseFactor(score, apyBps, timeDelta);

        assertGe(factor, RiskMath.MIN_REBASE_FACTOR, "Factor must be >= MIN_REBASE_FACTOR");
        assertLe(factor, RiskMath.MAX_REBASE_FACTOR, "Factor must be <= MAX_REBASE_FACTOR");
    }

    /// @notice clampFactor never returns a value outside bounds.
    function testFuzz_clampFactor(uint256 rawFactor) public pure {
        uint256 clamped = RiskMath.clampFactor(rawFactor);
        assertGe(clamped, RiskMath.MIN_REBASE_FACTOR, "Clamped factor >= MIN");
        assertLe(clamped, RiskMath.MAX_REBASE_FACTOR, "Clamped factor <= MAX");
    }

    /// @notice clampIndex never returns a value outside bounds.
    function testFuzz_clampIndex(uint256 rawIndex) public pure {
        uint256 clamped = RiskMath.clampIndex(rawIndex);
        assertGe(clamped, RiskMath.MIN_REBASE_INDEX, "Clamped index >= MIN");
        assertLe(clamped, RiskMath.MAX_REBASE_INDEX, "Clamped index <= MAX");
    }

    /// @notice applyRebase always produces an index within [MIN_INDEX, MAX_INDEX] (CRIT-02).
    function testFuzz_applyRebase_indexAlwaysInBounds(uint256 currentIndex, uint256 factor) public pure {
        currentIndex = bound(currentIndex, RiskMath.MIN_REBASE_INDEX, RiskMath.MAX_REBASE_INDEX);
        factor = bound(factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR);

        uint256 newIndex = RiskMath.applyRebase(currentIndex, factor);
        assertGe(newIndex, RiskMath.MIN_REBASE_INDEX, "New index must be >= MIN_REBASE_INDEX");
        assertLe(newIndex, RiskMath.MAX_REBASE_INDEX, "New index must be <= MAX_REBASE_INDEX");
    }

    /// @notice Risk level classification covers the full 0-100 range without gaps.
    function testFuzz_riskLevel_fullCoverage(uint256 score) public pure {
        score = bound(score, 0, 100);
        RiskLevel level = RiskMath.riskLevel(score);

        // Every score should map to exactly one tier
        assertTrue(
            level == RiskLevel.SAFE ||
            level == RiskLevel.CAUTION ||
            level == RiskLevel.DANGER ||
            level == RiskLevel.CRITICAL,
            "Score must map to a valid tier"
        );
    }

    /// @notice SAFE score always produces factor >= 1e18 (non-negative yield).
    function testFuzz_safeTier_nonNegativeYield(uint256 score, uint256 apyBps, uint256 timeDelta) public pure {
        score = bound(score, 0, 39);
        apyBps = bound(apyBps, 0, 3000);
        timeDelta = bound(timeDelta, 0, 1 days);

        uint256 factor = RiskMath.calculateRebaseFactor(score, apyBps, timeDelta);
        assertGe(factor, 1e18, "SAFE tier must never produce negative yield");
    }

    /// @notice CAUTION yields less than or equal to SAFE for same inputs.
    function testFuzz_cautionYield_lessOrEqualToSafe(uint256 apyBps, uint256 timeDelta) public pure {
        apyBps = bound(apyBps, 0, 3000);
        timeDelta = bound(timeDelta, 0, 1 days);

        uint256 safeFactor = RiskMath.calculateRebaseFactor(20, apyBps, timeDelta);
        uint256 cautionFactor = RiskMath.calculateRebaseFactor(50, apyBps, timeDelta);

        assertGe(safeFactor, cautionFactor, "SAFE yield must be >= CAUTION yield");
    }

    /// @notice DANGER always returns exactly 1e18 regardless of APY/time.
    function testFuzz_dangerTier_alwaysNeutral(uint256 score, uint256 apyBps, uint256 timeDelta) public pure {
        score = bound(score, 70, 89);
        apyBps = bound(apyBps, 0, 3000);
        timeDelta = bound(timeDelta, 0, 1 days);

        uint256 factor = RiskMath.calculateRebaseFactor(score, apyBps, timeDelta);
        assertEq(factor, 1e18, "DANGER tier must always return 1.0");
    }

    /// @notice CRITICAL always returns the fixed negative factor.
    function testFuzz_criticalTier_fixedNegative(uint256 score, uint256 apyBps, uint256 timeDelta) public pure {
        score = bound(score, 90, 100);
        apyBps = bound(apyBps, 0, 3000);
        timeDelta = bound(timeDelta, 0, 1 days);

        uint256 factor = RiskMath.calculateRebaseFactor(score, apyBps, timeDelta);
        assertEq(factor, RiskMath.CRITICAL_REBASE_FACTOR, "CRITICAL must return fixed -0.5% factor");
    }

    /// @notice absDiff is commutative.
    function testFuzz_absDiff_commutative(uint256 a, uint256 b) public pure {
        a = bound(a, 0, 100);
        b = bound(b, 0, 100);
        assertEq(RiskMath.absDiff(a, b), RiskMath.absDiff(b, a), "absDiff must be commutative");
    }
}
