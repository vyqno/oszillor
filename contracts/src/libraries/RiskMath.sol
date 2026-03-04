// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {RiskLevel} from "./DataStructures.sol";

/// @title RiskMath
/// @author Hitesh (vyqno)
/// @notice Pure risk tier classification and rebase factor calculation.
/// @dev All constants and logic for the OSZILLOR risk-reactive rebase model.
///
///      Risk tiers determine how yield is distributed:
///        SAFE     (0-39)  : 100% of weighted APY flows to holders.
///        CAUTION  (40-69) : 50% of weighted APY (de-risk buffer).
///        DANGER   (70-89) : 0% yield — balance holds steady.
///        CRITICAL (90-100): Negative rebase — protocol actively de-risks.
///
///      CRIT-02 fix: Hard bounds on both rebase factor and rebase index
///      prevent catastrophic outcomes (index going to 0 or overflowing).
library RiskMath {
    /// @notice 1e18 precision base for all factor/index arithmetic.
    uint256 internal constant PRECISION = 1e18;

    // ──────────────────── Risk Tier Thresholds ────────────────────

    /// @notice Scores below this are SAFE.
    uint256 internal constant SAFE_THRESHOLD = 40;

    /// @notice Scores at or above this enter CAUTION.
    uint256 internal constant CAUTION_THRESHOLD = 40;

    /// @notice Scores at or above this enter DANGER.
    uint256 internal constant DANGER_THRESHOLD = 70;

    /// @notice Scores at or above this enter CRITICAL.
    uint256 internal constant CRITICAL_THRESHOLD = 90;

    // ──────────────────── Rebase Factor Bounds (CRIT-02) ────────────────────

    /// @notice Maximum negative rebase per epoch (-1%).
    uint256 internal constant MIN_REBASE_FACTOR = 0.99e18;

    /// @notice Maximum positive rebase per epoch (+1%).
    uint256 internal constant MAX_REBASE_FACTOR = 1.01e18;

    // ──────────────────── Rebase Index Bounds (CRIT-02) ────────────────────

    /// @notice Floor index — 1% of initial (prevents near-zero balances).
    uint256 internal constant MIN_REBASE_INDEX = 1e16;

    /// @notice Ceiling index — 100x initial (prevents overflow in downstream math).
    uint256 internal constant MAX_REBASE_INDEX = 1e20;

    // ──────────────────── Time Constants ────────────────────

    /// @notice Seconds in a year (accounts for leap years).
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    /// @notice Fixed negative rebase factor for CRITICAL tier (-0.5% per epoch).
    uint256 internal constant CRITICAL_REBASE_FACTOR = 0.995e18;

    // ──────────────────── Risk Score Limits ────────────────────

    /// @notice Maximum allowed risk score delta per single CRE update.
    uint256 internal constant MAX_SCORE_DELTA = 20;

    /// @notice Minimum CRE DON consensus confidence to accept a report.
    uint256 internal constant MIN_CONFIDENCE = 60;

    /// @notice Minimum interval between consecutive risk updates (seconds).
    uint256 internal constant MIN_UPDATE_INTERVAL = 55;

    // ──────────────────── Functions ────────────────────

    /// @notice Classifies a 0-100 risk score into a RiskLevel tier.
    /// @param score The risk score to classify.
    /// @return level The corresponding risk tier.
    function riskLevel(uint256 score) internal pure returns (RiskLevel level) {
        if (score >= CRITICAL_THRESHOLD) return RiskLevel.CRITICAL;
        if (score >= DANGER_THRESHOLD) return RiskLevel.DANGER;
        if (score >= CAUTION_THRESHOLD) return RiskLevel.CAUTION;
        return RiskLevel.SAFE;
    }

    /// @notice Calculates the rebase factor based on risk score, weighted APY, and elapsed time.
    /// @dev Factor is always clamped to [MIN_REBASE_FACTOR, MAX_REBASE_FACTOR].
    ///      - SAFE:     factor = 1e18 + (weightedApyBps * timeDelta / SECONDS_PER_YEAR) * 1e18 / 10000
    ///      - CAUTION:  factor = 1e18 + 50% of the SAFE yield
    ///      - DANGER:   factor = 1e18 (no change)
    ///      - CRITICAL: factor = CRITICAL_REBASE_FACTOR (fixed -0.5%)
    /// @param score Current risk score (0-100).
    /// @param weightedApyBps Weighted average APY across allocations, in basis points.
    /// @param timeDelta Seconds elapsed since the last rebase.
    /// @return factor The multiplicative rebase factor (1e18 precision).
    function calculateRebaseFactor(uint256 score, uint256 weightedApyBps, uint256 timeDelta)
        internal
        pure
        returns (uint256 factor)
    {
        RiskLevel level = riskLevel(score);

        if (level == RiskLevel.CRITICAL) {
            return CRITICAL_REBASE_FACTOR;
        }

        if (level == RiskLevel.DANGER) {
            return PRECISION;
        }

        // Calculate period yield: (APY_bps * timeDelta) / (SECONDS_PER_YEAR * 10000)
        // Multiply by PRECISION first to maintain precision
        uint256 periodYield = Math.mulDiv(
            weightedApyBps * timeDelta,
            PRECISION,
            SECONDS_PER_YEAR * 10_000
        );

        if (level == RiskLevel.CAUTION) {
            periodYield = periodYield / 2; // 50% yield
        }
        // SAFE: 100% yield (no adjustment)

        factor = clampFactor(PRECISION + periodYield);
    }

    /// @notice Clamps a rebase factor to the allowed safety bounds.
    /// @param factor Raw factor to clamp.
    /// @return clamped Factor within [MIN_REBASE_FACTOR, MAX_REBASE_FACTOR].
    function clampFactor(uint256 factor) internal pure returns (uint256 clamped) {
        if (factor < MIN_REBASE_FACTOR) return MIN_REBASE_FACTOR;
        if (factor > MAX_REBASE_FACTOR) return MAX_REBASE_FACTOR;
        return factor;
    }

    /// @notice Clamps a rebase index to the allowed safety bounds.
    /// @param index Raw index to clamp.
    /// @return clamped Index within [MIN_REBASE_INDEX, MAX_REBASE_INDEX].
    function clampIndex(uint256 index) internal pure returns (uint256 clamped) {
        if (index < MIN_REBASE_INDEX) return MIN_REBASE_INDEX;
        if (index > MAX_REBASE_INDEX) return MAX_REBASE_INDEX;
        return index;
    }

    /// @notice Applies a rebase factor to the current index with safety clamping.
    /// @dev newIndex = clamp(currentIndex * factor / 1e18).
    /// @param currentIndex The current rebase index.
    /// @param factor The multiplicative factor to apply.
    /// @return newIndex The resulting rebase index, clamped to bounds.
    function applyRebase(uint256 currentIndex, uint256 factor) internal pure returns (uint256 newIndex) {
        newIndex = Math.mulDiv(currentIndex, factor, PRECISION);
        newIndex = clampIndex(newIndex);
    }

    /// @notice Computes the absolute difference between two values.
    /// @param a First value.
    /// @param b Second value.
    /// @return delta |a - b|
    function absDiff(uint256 a, uint256 b) internal pure returns (uint256 delta) {
        delta = a > b ? a - b : b - a;
    }
}
