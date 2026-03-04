// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskLevel} from "../../src/libraries/DataStructures.sol";

/// @title LibrariesTest
/// @author Hitesh (vyqno)
/// @notice Unit tests for OSZILLOR Layer 1 libraries (ShareMath, RiskMath, Roles).
contract LibrariesTest is Test {
    // ═══════════════════════════════════════════════════════════════
    //                          ROLES
    // ═══════════════════════════════════════════════════════════════

    function test_roles_areDistinct() public pure {
        bytes32[9] memory roles = [
            Roles.CONFIG_ADMIN_ROLE,
            Roles.CROSS_CHAIN_ADMIN_ROLE,
            Roles.RISK_MANAGER_ROLE,
            Roles.REBASE_EXECUTOR_ROLE,
            Roles.SENTINEL_ROLE,
            Roles.EMERGENCY_PAUSER_ROLE,
            Roles.EMERGENCY_UNPAUSER_ROLE,
            Roles.FEE_RATE_SETTER_ROLE,
            Roles.FEE_WITHDRAWER_ROLE
        ];

        for (uint256 i = 0; i < roles.length; i++) {
            assertTrue(roles[i] != bytes32(0), "Role should not be zero");
            for (uint256 j = i + 1; j < roles.length; j++) {
                assertTrue(roles[i] != roles[j], "Roles must be unique");
            }
        }
    }

    function test_roles_areKeccak256() public pure {
        assertEq(Roles.CONFIG_ADMIN_ROLE, keccak256("CONFIG_ADMIN_ROLE"));
        assertEq(Roles.RISK_MANAGER_ROLE, keccak256("RISK_MANAGER_ROLE"));
        assertEq(Roles.REBASE_EXECUTOR_ROLE, keccak256("REBASE_EXECUTOR_ROLE"));
        assertEq(Roles.SENTINEL_ROLE, keccak256("SENTINEL_ROLE"));
        assertEq(Roles.FEE_WITHDRAWER_ROLE, keccak256("FEE_WITHDRAWER_ROLE"));
    }

    // ═══════════════════════════════════════════════════════════════
    //                      SHARE MATH — VAULT-BASED
    // ═══════════════════════════════════════════════════════════════

    function test_sharemath_firstDeposit_getsShares() public pure {
        // First depositor with zero existing shares/assets
        uint256 shares = ShareMath.amountToShares(1_000_000, 0, 0);
        assertGt(shares, 0, "First deposit must produce shares");
    }

    function test_sharemath_virtualOffset_preventsInflation() public pure {
        // CRIT-01: Attacker deposits 1 wei, donates 1M, victim deposits 999_999
        // With virtual offset, victim should still get > 0 shares

        // Attacker deposit: 1 wei
        uint256 attackerShares = ShareMath.amountToShares(1, 0, 0);
        assertGt(attackerShares, 0, "Attacker gets shares");

        // Simulate donation: totalAssets = 1 + 1_000_000 = 1_000_001, totalShares = attackerShares
        // Victim deposits 999_999
        uint256 victimShares = ShareMath.amountToShares(999_999, attackerShares, 1_000_001);
        assertGt(victimShares, 0, "CRIT-01: Victim must get shares even after donation");
    }

    function test_sharemath_depositWithdrawRoundtrip() public pure {
        uint256 depositAmount = 1_000_000; // 1 USDC (6 decimals)
        uint256 totalShares = 5_000_000;
        uint256 totalAssets = 5_000_000;

        uint256 shares = ShareMath.amountToShares(depositAmount, totalShares, totalAssets);
        uint256 recovered = ShareMath.sharesToAmount(shares, totalShares + shares, totalAssets + depositAmount);

        // At most 1 wei rounding loss
        assertApproxEqAbs(recovered, depositAmount, 1, "Round-trip should lose at most 1 wei");
    }

    function test_sharemath_protocolFavored_onDeposit() public pure {
        // Rounding should favor the vault (depositor gets fewer shares, not more)
        uint256 amount = 3;
        uint256 totalShares = 7;
        uint256 totalAssets = 10;

        uint256 shares = ShareMath.amountToShares(amount, totalShares, totalAssets);
        uint256 value = ShareMath.sharesToAmount(shares, totalShares, totalAssets);

        // Depositor's shares should be worth <= deposit amount (vault keeps the dust)
        assertLe(value, amount, "Rounding must favor protocol on deposit");
    }

    // ═══════════════════════════════════════════════════════════════
    //                    SHARE MATH — INDEX-BASED
    // ═══════════════════════════════════════════════════════════════

    function test_sharemath_indexRoundtrip() public pure {
        uint256 amount = 1_000_000;
        uint256 rebaseIndex = 1.05e18; // 5% appreciation

        uint256 shares = ShareMath.amountToSharesByIndex(amount, rebaseIndex);
        uint256 recovered = ShareMath.sharesToAmountByIndex(shares, rebaseIndex);

        assertApproxEqAbs(recovered, amount, 1, "Index round-trip should lose at most 1 wei");
    }

    function test_sharemath_indexAtPrecision() public pure {
        // At 1e18 index, shares == amounts
        uint256 amount = 500_000;
        uint256 shares = ShareMath.amountToSharesByIndex(amount, 1e18);
        assertEq(shares, amount, "At 1e18 index, shares should equal amounts");
    }

    function test_sharemath_indexAbovePrecision_fewerShares() public pure {
        // When index > 1e18, each share is worth more, so fewer shares per amount
        uint256 amount = 1_000_000;
        uint256 shares = ShareMath.amountToSharesByIndex(amount, 2e18);
        assertEq(shares, 500_000, "At 2e18 index, 1M amount = 500K shares");
    }

    // ═══════════════════════════════════════════════════════════════
    //                    RISK MATH — TIER CLASSIFICATION
    // ═══════════════════════════════════════════════════════════════

    function test_riskmath_safeTier() public pure {
        assertEq(uint256(RiskMath.riskLevel(0)), uint256(RiskLevel.SAFE));
        assertEq(uint256(RiskMath.riskLevel(20)), uint256(RiskLevel.SAFE));
        assertEq(uint256(RiskMath.riskLevel(39)), uint256(RiskLevel.SAFE));
    }

    function test_riskmath_cautionTier() public pure {
        assertEq(uint256(RiskMath.riskLevel(40)), uint256(RiskLevel.CAUTION));
        assertEq(uint256(RiskMath.riskLevel(55)), uint256(RiskLevel.CAUTION));
        assertEq(uint256(RiskMath.riskLevel(69)), uint256(RiskLevel.CAUTION));
    }

    function test_riskmath_dangerTier() public pure {
        assertEq(uint256(RiskMath.riskLevel(70)), uint256(RiskLevel.DANGER));
        assertEq(uint256(RiskMath.riskLevel(80)), uint256(RiskLevel.DANGER));
        assertEq(uint256(RiskMath.riskLevel(89)), uint256(RiskLevel.DANGER));
    }

    function test_riskmath_criticalTier() public pure {
        assertEq(uint256(RiskMath.riskLevel(90)), uint256(RiskLevel.CRITICAL));
        assertEq(uint256(RiskMath.riskLevel(95)), uint256(RiskLevel.CRITICAL));
        assertEq(uint256(RiskMath.riskLevel(100)), uint256(RiskLevel.CRITICAL));
    }

    // ═══════════════════════════════════════════════════════════════
    //                RISK MATH — REBASE FACTOR CALCULATION
    // ═══════════════════════════════════════════════════════════════

    function test_riskmath_safeFactor_positiveYield() public pure {
        // SAFE tier: 100% of 5% APY over 5 minutes
        uint256 factor = RiskMath.calculateRebaseFactor(20, 500, 300);
        assertGt(factor, 1e18, "SAFE factor must be > 1.0");
        assertLe(factor, RiskMath.MAX_REBASE_FACTOR, "Factor must be within bounds");
    }

    function test_riskmath_cautionFactor_halfYield() public pure {
        // CAUTION: 50% of the SAFE yield
        uint256 safeFactor = RiskMath.calculateRebaseFactor(20, 500, 300);
        uint256 cautionFactor = RiskMath.calculateRebaseFactor(50, 500, 300);

        uint256 safeYield = safeFactor - 1e18;
        uint256 cautionYield = cautionFactor - 1e18;

        // CAUTION yield should be approximately half of SAFE yield
        assertApproxEqAbs(cautionYield, safeYield / 2, 1, "CAUTION yield should be ~50% of SAFE");
    }

    function test_riskmath_dangerFactor_noChange() public pure {
        uint256 factor = RiskMath.calculateRebaseFactor(75, 500, 300);
        assertEq(factor, 1e18, "DANGER factor must be exactly 1.0");
    }

    function test_riskmath_criticalFactor_negativeRebase() public pure {
        uint256 factor = RiskMath.calculateRebaseFactor(95, 500, 300);
        assertEq(factor, RiskMath.CRITICAL_REBASE_FACTOR, "CRITICAL factor must be 0.995e18");
        assertLt(factor, 1e18, "CRITICAL factor must be < 1.0");
    }

    function test_riskmath_zeroApy_safeFactor_noYield() public pure {
        uint256 factor = RiskMath.calculateRebaseFactor(20, 0, 300);
        assertEq(factor, 1e18, "Zero APY should produce factor of 1.0");
    }

    function test_riskmath_zeroTimeDelta_noYield() public pure {
        uint256 factor = RiskMath.calculateRebaseFactor(20, 500, 0);
        assertEq(factor, 1e18, "Zero time delta should produce factor of 1.0");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  RISK MATH — FACTOR CLAMPING (CRIT-02)
    // ═══════════════════════════════════════════════════════════════

    function test_riskmath_clampFactor_withinBounds() public pure {
        assertEq(RiskMath.clampFactor(1e18), 1e18, "1.0 should pass through");
        assertEq(RiskMath.clampFactor(1.005e18), 1.005e18, "1.005 should pass through");
    }

    function test_riskmath_clampFactor_belowMin() public pure {
        assertEq(RiskMath.clampFactor(0.98e18), RiskMath.MIN_REBASE_FACTOR, "Below min should clamp to min");
        assertEq(RiskMath.clampFactor(0), RiskMath.MIN_REBASE_FACTOR, "Zero should clamp to min");
    }

    function test_riskmath_clampFactor_aboveMax() public pure {
        assertEq(RiskMath.clampFactor(1.02e18), RiskMath.MAX_REBASE_FACTOR, "Above max should clamp to max");
        assertEq(RiskMath.clampFactor(2e18), RiskMath.MAX_REBASE_FACTOR, "2x should clamp to max");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  RISK MATH — INDEX CLAMPING (CRIT-02)
    // ═══════════════════════════════════════════════════════════════

    function test_riskmath_clampIndex_withinBounds() public pure {
        assertEq(RiskMath.clampIndex(1e18), 1e18, "1e18 should pass through");
        assertEq(RiskMath.clampIndex(5e18), 5e18, "5e18 should pass through");
    }

    function test_riskmath_clampIndex_belowMin() public pure {
        assertEq(RiskMath.clampIndex(1e15), RiskMath.MIN_REBASE_INDEX, "Below min should clamp");
        assertEq(RiskMath.clampIndex(0), RiskMath.MIN_REBASE_INDEX, "Zero should clamp to min");
    }

    function test_riskmath_clampIndex_aboveMax() public pure {
        assertEq(RiskMath.clampIndex(1e21), RiskMath.MAX_REBASE_INDEX, "Above max should clamp");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  RISK MATH — APPLY REBASE
    // ═══════════════════════════════════════════════════════════════

    function test_riskmath_applyRebase_neutral() public pure {
        uint256 newIndex = RiskMath.applyRebase(1e18, 1e18);
        assertEq(newIndex, 1e18, "Neutral rebase should not change index");
    }

    function test_riskmath_applyRebase_positive() public pure {
        uint256 newIndex = RiskMath.applyRebase(1e18, 1.005e18);
        assertEq(newIndex, 1.005e18, "Positive rebase should increase index");
    }

    function test_riskmath_applyRebase_negative() public pure {
        uint256 newIndex = RiskMath.applyRebase(1e18, 0.995e18);
        assertEq(newIndex, 0.995e18, "Negative rebase should decrease index");
    }

    function test_riskmath_applyRebase_clampsToFloor() public pure {
        // Start at MIN_REBASE_INDEX and apply a negative factor
        uint256 newIndex = RiskMath.applyRebase(RiskMath.MIN_REBASE_INDEX, RiskMath.MIN_REBASE_FACTOR);
        assertGe(newIndex, RiskMath.MIN_REBASE_INDEX, "Index must never go below floor");
    }

    function test_riskmath_applyRebase_clampsToCeiling() public pure {
        // Start at MAX_REBASE_INDEX and apply a positive factor
        uint256 newIndex = RiskMath.applyRebase(RiskMath.MAX_REBASE_INDEX, RiskMath.MAX_REBASE_FACTOR);
        assertLe(newIndex, RiskMath.MAX_REBASE_INDEX, "Index must never exceed ceiling");
    }

    // ═══════════════════════════════════════════════════════════════
    //                  RISK MATH — ABS DIFF
    // ═══════════════════════════════════════════════════════════════

    function test_riskmath_absDiff() public pure {
        assertEq(RiskMath.absDiff(50, 30), 20);
        assertEq(RiskMath.absDiff(30, 50), 20);
        assertEq(RiskMath.absDiff(50, 50), 0);
        assertEq(RiskMath.absDiff(0, 100), 100);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    RISK MATH — CONSTANTS
    // ═══════════════════════════════════════════════════════════════

    function test_riskmath_constantsConsistency() public pure {
        // Thresholds must be in ascending order
        assertLt(RiskMath.CAUTION_THRESHOLD, RiskMath.DANGER_THRESHOLD);
        assertLt(RiskMath.DANGER_THRESHOLD, RiskMath.CRITICAL_THRESHOLD);

        // Factor bounds must bracket 1.0
        assertLt(RiskMath.MIN_REBASE_FACTOR, 1e18);
        assertGt(RiskMath.MAX_REBASE_FACTOR, 1e18);

        // Index bounds must bracket 1e18
        assertLt(RiskMath.MIN_REBASE_INDEX, 1e18);
        assertGt(RiskMath.MAX_REBASE_INDEX, 1e18);

        // Critical factor must be within bounds
        assertGe(RiskMath.CRITICAL_REBASE_FACTOR, RiskMath.MIN_REBASE_FACTOR);
        assertLt(RiskMath.CRITICAL_REBASE_FACTOR, 1e18);
    }
}
