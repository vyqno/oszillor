// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CREReceiver} from "./CREReceiver.sol";
import {IOszillorVault} from "../interfaces/IOszillorVault.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {RiskMath} from "../libraries/RiskMath.sol";
import {RiskReport} from "../libraries/DataStructures.sol";

/// @title RiskEngine
/// @author Hitesh (vyqno)
/// @notice CRE W1 receiver — processes risk reports and updates vault risk state.
/// @dev Extends CREReceiver with rate limiting (HIGH-05), confidence gating (HIGH-05),
///      delta clamping (HIGH-10), and pause checking (HIGH-08). Uses typed interface
///      calls to vault — never raw `.call()` (anti-pattern from plan.md Section 13).
contract RiskEngine is CREReceiver {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a risk score warning crosses the CRITICAL threshold.
    /// @param newScore The new risk score.
    /// @param previousScore The previous risk score.
    /// @param negativeRebaseImminent Whether a negative rebase is expected next W3 cycle.
    event RiskScoreWarning(uint256 indexed newScore, uint256 previousScore, bool negativeRebaseImminent);

    /// @notice Emitted when a risk report is processed successfully.
    /// @param riskScore Updated risk score.
    /// @param confidence DON consensus confidence.
    /// @param reasoningHash Audit trail for AI reasoning.
    event RiskReportProcessed(uint256 riskScore, uint256 confidence, bytes32 reasoningHash);

    // ──────────────────── Constants ────────────────────

    /// @notice Minimum seconds between consecutive risk updates (HIGH-05 fix).
    uint256 public constant MIN_UPDATE_INTERVAL = 55 seconds;

    /// @notice Maximum risk score delta per single update (HIGH-10 fix).
    uint256 public constant MAX_SCORE_JUMP = 20;

    /// @notice Minimum DON consensus confidence to accept a report (HIGH-05 fix).
    uint256 public constant MIN_CONFIDENCE = 60;

    // ──────────────────── State ────────────────────

    /// @notice Reference to the OszillorVault for typed interface calls.
    IOszillorVault public immutable vault;

    /// @notice Timestamp of the last accepted risk update.
    uint256 public lastRiskUpdate;

    /// @notice External pause check — the contract whose pause state we respect.
    /// @dev Set to the PausableWithAccessControl address (vault or hub).
    address public immutable pauseChecker;

    /// @notice Constructs the RiskEngine with its vault reference and CRE params.
    /// @param _vault Address of the OszillorVault contract.
    /// @param _pauseChecker Address of the pausable contract to check state.
    /// @param _forwarder CRE forwarder address.
    /// @param _workflowId CRE workflow CID.
    /// @param _workflowName CRE workflow name.
    /// @param _workflowOwner CRE workflow owner.
    constructor(
        address _vault,
        address _pauseChecker,
        address _forwarder,
        bytes32 _workflowId,
        bytes10 _workflowName,
        address _workflowOwner
    ) CREReceiver(_forwarder, _workflowId, _workflowName, _workflowOwner) {
        vault = IOszillorVault(_vault);
        pauseChecker = _pauseChecker;
    }

    /// @notice Processes a validated W1 risk report.
    /// @dev Applies rate limit, confidence gate, delta clamp, and pause check.
    ///      Calls vault.updateRiskScore() and vault.updateAllocations() via typed interface.
    /// @param report ABI-encoded RiskReport struct.
    function _handleReport(bytes calldata report) internal override {
        // HIGH-08: Check pause state
        _requireNotPaused();

        // Decode the report
        RiskReport memory riskReport = abi.decode(report, (RiskReport));

        // LOW-NEW-01 fix: Bounds check on risk score
        if (riskReport.riskScore > 100) {
            revert OszillorErrors.InvalidRiskScore(riskReport.riskScore);
        }

        // HIGH-05: Rate limit — min 55s between updates
        if (block.timestamp < lastRiskUpdate + MIN_UPDATE_INTERVAL) {
            revert OszillorErrors.UpdateTooFrequent(lastRiskUpdate + MIN_UPDATE_INTERVAL);
        }

        // HIGH-05: Confidence gate — reject low-confidence reports
        if (riskReport.confidence < MIN_CONFIDENCE) {
            revert OszillorErrors.ConfidenceTooLow(riskReport.confidence, MIN_CONFIDENCE);
        }

        // HIGH-10: Delta clamp — max 20-point jump per update
        uint256 currentScore = vault.currentRiskScore();
        uint256 delta = riskReport.riskScore > currentScore
            ? riskReport.riskScore - currentScore
            : currentScore - riskReport.riskScore;

        if (delta > MAX_SCORE_JUMP) {
            revert OszillorErrors.ScoreJumpTooLarge(delta, MAX_SCORE_JUMP);
        }

        // Update timestamp
        lastRiskUpdate = block.timestamp;

        // MED-07: Emit warning when crossing CRITICAL threshold
        bool crossingCritical = riskReport.riskScore >= RiskMath.CRITICAL_THRESHOLD
            && currentScore < RiskMath.CRITICAL_THRESHOLD;
        if (crossingCritical) {
            emit RiskScoreWarning(riskReport.riskScore, currentScore, true);
        }

        // Update vault risk score via typed interface (NEVER raw .call())
        vault.updateRiskScore(
            riskReport.riskScore,
            riskReport.confidence,
            riskReport.reasoningHash
        );

        // Update allocations if provided
        if (riskReport.allocations.length > 0) {
            // Memory-to-calldata requires encoding; use the vault interface
            vault.updateAllocations(riskReport.allocations);
        }

        emit RiskReportProcessed(
            riskReport.riskScore,
            riskReport.confidence,
            riskReport.reasoningHash
        );
    }

    /// @notice Checks that the pause-checker contract is not paused.
    /// @dev Uses typed Pausable interface — never raw staticcall.
    function _requireNotPaused() internal view {
        if (Pausable(pauseChecker).paused()) {
            revert OszillorErrors.SystemPaused();
        }
    }
}
