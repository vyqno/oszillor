// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {RebaseExecutor} from "../../src/modules/RebaseExecutor.sol";
import {EventSentinel} from "../../src/modules/EventSentinel.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {RiskReport, RebalanceReport, ThreatReport, Allocation, RiskLevel} from "../../src/libraries/DataStructures.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPausable} from "../mocks/MockPausable.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";

/// @title CREIntegrationTest
/// @author Hitesh (vyqno)
/// @notice End-to-end integration test: real contracts wired together,
///         simulating the full CRE workflow → Vault lifecycle.
///         Forwarder calls are simulated with vm.prank, matching how
///         KeystoneForwarder delivers signed reports in production.
contract CREIntegrationTest is Test {
    // ──────────────────── Actors ────────────────────
    address admin = makeAddr("admin");
    address user = makeAddr("user");
    address feeRecipient = makeAddr("treasury");
    address forwarder = makeAddr("forwarder");
    address workflowOwner = makeAddr("workflowOwner");

    // Each CRE receiver has its own workflow identity
    bytes32 riskWfId = keccak256("risk-scanner-v1");
    bytes10 riskWfName = bytes10(keccak256("w1-risk"));
    bytes32 rebaseWfId = keccak256("rebase-executor-v1");
    bytes10 rebaseWfName = bytes10(keccak256("w3-rebase"));
    bytes32 sentinelWfId = keccak256("event-sentinel-v1");
    bytes10 sentinelWfName = bytes10(keccak256("w2-event"));

    // ──────────────────── Contracts ────────────────────
    MockERC20 usdc;
    MockPausable pausable;
    MockStrategy strategy;
    OszillorToken token;
    OszillorVault vault;
    RiskEngine riskEngine;
    RebaseExecutor rebaseExecutor;
    EventSentinel eventSentinel;

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.startPrank(admin);

        usdc = new MockERC20();
        pausable = new MockPausable();
        strategy = new MockStrategy();
        token = new OszillorToken("OSZILLOR", "OSZ", admin);

        // Predict vault address — modules need it at construction time
        uint64 nonce = vm.getNonce(admin);
        address predictedVault = vm.computeCreateAddress(admin, nonce + 3);

        // Deploy CRE receivers pointing to predicted vault
        riskEngine = new RiskEngine(
            predictedVault, address(pausable),
            forwarder, riskWfId, riskWfName, workflowOwner
        );
        rebaseExecutor = new RebaseExecutor(
            predictedVault, address(pausable),
            forwarder, rebaseWfId, rebaseWfName, workflowOwner
        );
        eventSentinel = new EventSentinel(
            predictedVault,
            forwarder, sentinelWfId, sentinelWfName, workflowOwner
        );

        // Deploy vault — grants roles to modules in constructor
        vault = new OszillorVault(
            address(usdc), address(token),
            address(riskEngine), address(rebaseExecutor), address(eventSentinel),
            address(strategy), admin, feeRecipient
        );
        assertEq(address(vault), predictedVault, "vault address prediction failed");

        // Grant token roles to vault (for mintShares, burnShares, rebase)
        token.grantRole(Roles.RISK_MANAGER_ROLE, address(vault));
        token.grantRole(Roles.REBASE_EXECUTOR_ROLE, address(vault));

        vm.stopPrank();

        // Fund user with 10,000 tokens and pre-approve vault
        usdc.mint(user, 10_000e18);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════
    //   E2E 1: Deposit → Risk Update → Positive Rebase → Balance Up
    // ═══════════════════════════════════════════════════════════════

    function test_e2e_depositAndPositiveRebase() public {
        // Step 1: User deposits 1000 tokens
        vm.prank(user);
        vault.deposit(1000e18);

        uint256 balBefore = token.balanceOf(user);
        assertGt(balBefore, 0, "should have token balance after deposit");

        // Step 2: W1 — RiskEngine receives SAFE risk score (35)
        // Delta from initial 50 → 35 = 15 (within MAX_SCORE_JUMP=20)
        _sendRiskReport(35, 85);
        assertEq(vault.currentRiskScore(), 35);

        // Step 3: W3 — RebaseExecutor applies +0.5% positive rebase
        _sendRebaseReport(1.005e18, 35, 500, 300);

        uint256 balAfter = token.balanceOf(user);
        assertGt(balAfter, balBefore, "balance should increase after positive rebase");
        assertGt(token.rebaseIndex(), 1e18, "index should be above initial 1e18");
    }

    // ═══════════════════════════════════════════════════════════════
    //   E2E 2: Emergency Halt → Deposits Blocked → Expiry → Resume
    // ═══════════════════════════════════════════════════════════════

    function test_e2e_emergencyBlocksDepositsAndExpires() public {
        // Step 1: User deposits 1000 tokens
        vm.prank(user);
        vault.deposit(1000e18);

        // Step 2: W2 — EventSentinel triggers emergency (2 hours)
        _sendThreatReport(true, 2 hours);
        assertTrue(vault.emergencyMode(), "emergency mode should be active");

        // Step 3: Deposits are blocked during emergency
        vm.prank(user);
        vm.expectRevert();
        vault.deposit(100e18);

        // Step 4: Withdrawals ALWAYS work — even during emergency (HIGH-06)
        uint256 shares = token.sharesOf(user);
        vm.prank(user);
        uint256 withdrawn = vault.withdraw(shares / 2);
        assertGt(withdrawn, 0, "withdrawal should succeed during emergency");

        // Step 5: Warp past emergency expiry
        vm.warp(block.timestamp + 2 hours + 1);
        assertFalse(vault.emergencyMode(), "emergency should have expired");

        // Step 6: Deposits resume after expiry
        vm.prank(user);
        vault.deposit(100e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //   E2E 3: Risk Escalation to CRITICAL → Negative Rebase
    // ═══════════════════════════════════════════════════════════════

    function test_e2e_criticalRiskNegativeRebase() public {
        // Step 1: Deposit
        vm.prank(user);
        vault.deposit(1000e18);
        uint256 balAfterDeposit = token.balanceOf(user);

        // Step 2: Escalate risk 50 → 70 (DANGER tier, delta=20)
        _sendRiskReport(70, 85);
        assertEq(vault.currentRiskScore(), 70);

        // Step 3: Wait rate limit, escalate 70 → 90 (CRITICAL tier, delta=20)
        vm.warp(block.timestamp + 56 seconds);
        _sendRiskReport(90, 85);
        assertEq(vault.currentRiskScore(), 90);

        // Step 4: W3 — CRITICAL rebase factor = 0.995e18 (-0.5%)
        _sendRebaseReport(RiskMath.CRITICAL_REBASE_FACTOR, 90, 500, 300);

        uint256 balAfterCritical = token.balanceOf(user);
        assertLt(balAfterCritical, balAfterDeposit, "balance should decrease after negative rebase");
        assertLt(token.rebaseIndex(), 1e18, "index should be below initial 1e18");
    }

    // ═══════════════════════════════════════════════════════════════
    //   E2E 4: Full Lifecycle (deposit → grow → danger → emergency → withdraw)
    // ═══════════════════════════════════════════════════════════════

    function test_e2e_fullLifecycle() public {
        // ── Phase 1: Deposit ──
        vm.prank(user);
        vault.deposit(5000e18);
        uint256 initialBal = token.balanceOf(user);
        assertGt(initialBal, 0);

        // ── Phase 2: SAFE risk + positive rebase ──
        _sendRiskReport(35, 85); // 50 → 35
        _sendRebaseReport(1.005e18, 35, 500, 300);
        uint256 balAfterGrowth = token.balanceOf(user);
        assertGt(balAfterGrowth, initialBal, "positive rebase should grow balance");

        // ── Phase 3: Escalate to DANGER tier ──
        vm.warp(block.timestamp + 56 seconds);
        _sendRiskReport(55, 85); // 35 → 55 (delta=20)
        vm.warp(block.timestamp + 56 seconds);
        _sendRiskReport(70, 85); // 55 → 70 (delta=15)

        // DANGER → factor 1e18 (no change)
        _sendRebaseReport(1e18, 70, 500, 300);
        assertEq(token.balanceOf(user), balAfterGrowth, "DANGER rebase should not change balance");

        // ── Phase 4: Emergency halt ──
        _sendThreatReport(true, 1 hours);
        assertTrue(vault.emergencyMode());

        // Withdrawals still work during emergency
        uint256 shares = token.sharesOf(user);
        vm.prank(user);
        uint256 partialWithdraw = vault.withdraw(shares / 4);
        assertGt(partialWithdraw, 0);

        // ── Phase 5: Emergency expires → deposits resume ──
        vm.warp(block.timestamp + 1 hours + 1);
        assertFalse(vault.emergencyMode());

        vm.prank(user);
        vault.deposit(1000e18);

        // ── Phase 6: Full withdrawal ──
        uint256 finalShares = token.sharesOf(user);
        vm.prank(user);
        uint256 finalWithdrawn = vault.withdraw(finalShares);
        assertGt(finalWithdrawn, 0);
        assertEq(token.sharesOf(user), 0, "should have zero shares after full withdrawal");
    }

    // ═══════════════════════════════════════════════════════════════
    //   E2E 5: Cross-Workflow Independence
    // ═══════════════════════════════════════════════════════════════

    function test_e2e_crossWorkflowIndependence() public {
        vm.prank(user);
        vault.deposit(1000e18);

        // W1: risk update succeeds
        _sendRiskReport(35, 85);

        // W3: rebase can happen immediately (separate receiver, no shared rate limit)
        _sendRebaseReport(1.003e18, 35, 300, 300);

        // W2: threat report also independent
        _sendThreatReport(false, 0); // non-emergency, just emits event

        // W1: second risk update within 55s → blocked by rate limit
        bytes memory metadata = _buildMetadata(riskWfId, riskWfName, workflowOwner);
        bytes memory report = _buildRiskReport(40, 85, bytes32(uint256(2)));
        vm.prank(forwarder);
        vm.expectRevert();
        riskEngine.onReport(metadata, report);

        // After rate limit passes, W1 works again
        vm.warp(block.timestamp + 56 seconds);
        _sendRiskReport(40, 85); // 35 → 40 (delta=5)
        assertEq(vault.currentRiskScore(), 40);
    }

    // ═══════════════════════════════════════════════════════════════
    //   E2E 6: Multiple Rebases Compound the Index
    // ═══════════════════════════════════════════════════════════════

    function test_e2e_compoundingRebases() public {
        vm.prank(user);
        vault.deposit(1000e18);

        // Set SAFE risk
        _sendRiskReport(35, 85);

        uint256 balBefore = token.balanceOf(user);

        // Apply 3 consecutive positive rebases (+0.3% each)
        _sendRebaseReport(1.003e18, 35, 300, 300);
        _sendRebaseReport(1.003e18, 35, 300, 300);
        _sendRebaseReport(1.003e18, 35, 300, 300);

        uint256 balAfter = token.balanceOf(user);
        assertGt(balAfter, balBefore, "compounding rebases should increase balance");

        // Index should compound: 1e18 * 1.003 * 1.003 * 1.003 ≈ 1.009027e18
        uint256 idx = token.rebaseIndex();
        assertGt(idx, 1.009e18, "index should compound above 1.009e18");
        assertLt(idx, 1.010e18, "index should be below 1.010e18");
    }

    // ═══════════════════════════════════════════════════════════════
    //                    INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════

    /// @dev Builds CRE metadata matching KeystoneFeedDefaultMetadataLib layout.
    function _buildMetadata(
        bytes32 wfId,
        bytes10 wfName,
        address wfOwner
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(wfId, wfName, wfOwner, bytes2(0));
    }

    function _buildRiskReport(
        uint256 score,
        uint256 confidence,
        bytes32 reasoningHash
    ) internal pure returns (bytes memory) {
        Allocation[] memory allocs = new Allocation[](0);
        return abi.encode(RiskReport({
            riskScore: score,
            confidence: confidence,
            reasoningHash: reasoningHash,
            allocations: allocs
        }));
    }

    function _buildRebaseReport(
        uint256 factor,
        uint256 riskScore,
        uint256 weightedApyBps,
        uint256 timeDelta
    ) internal pure returns (bytes memory) {
        // v2: RebaseExecutor now decodes RebalanceReport (adds targetEthPct)
        return abi.encode(RebalanceReport({
            rebaseFactor: factor,
            currentRiskScore: riskScore,
            targetEthPct: 10_000,
            weightedApyBps: weightedApyBps,
            timeDelta: timeDelta
        }));
    }

    function _buildThreatReport(
        bool emergencyHalt,
        uint256 suggestedDuration
    ) internal pure returns (bytes memory) {
        return abi.encode(ThreatReport({
            level: RiskLevel.CRITICAL,
            threatType: keccak256("depeg"),
            riskAdjustment: 30,
            emergencyHalt: emergencyHalt,
            suggestedDuration: suggestedDuration,
            reason: "USDC depeg detected"
        }));
    }

    /// @dev Sends a W1 risk report to the RiskEngine.
    function _sendRiskReport(uint256 score, uint256 confidence) internal {
        bytes memory metadata = _buildMetadata(riskWfId, riskWfName, workflowOwner);
        bytes memory report = _buildRiskReport(
            score, confidence, keccak256(abi.encode(score, block.timestamp))
        );
        vm.prank(forwarder);
        riskEngine.onReport(metadata, report);
    }

    /// @dev Sends a W3 rebase report to the RebaseExecutor.
    function _sendRebaseReport(
        uint256 factor, uint256 riskScore, uint256 apyBps, uint256 timeDelta
    ) internal {
        bytes memory metadata = _buildMetadata(rebaseWfId, rebaseWfName, workflowOwner);
        bytes memory report = _buildRebaseReport(factor, riskScore, apyBps, timeDelta);
        vm.prank(forwarder);
        rebaseExecutor.onReport(metadata, report);
    }

    /// @dev Sends a W2 threat report to the EventSentinel.
    function _sendThreatReport(bool emergency, uint256 duration) internal {
        bytes memory metadata = _buildMetadata(sentinelWfId, sentinelWfName, workflowOwner);
        bytes memory report = _buildThreatReport(emergency, duration);
        vm.prank(forwarder);
        eventSentinel.onReport(metadata, report);
    }
}
