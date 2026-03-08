// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CREReceiver} from "./CREReceiver.sol";
import {IOszillorVault} from "../interfaces/IOszillorVault.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {ThreatReport} from "../libraries/DataStructures.sol";

/// @title EventSentinel
/// @author Hitesh (vyqno)
/// @notice CRE W2 receiver — classifies threats and triggers emergency de-risk.
/// @dev Extends CREReceiver. Duration is bounded to MAX_EMERGENCY_DURATION (4 hours).
///      After expiry, deposit() auto-lifts the block (HIGH-06 fix). Manual early
///      exit via EMERGENCY_UNPAUSER_ROLE on the vault.
contract EventSentinel is CREReceiver {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a threat report triggers emergency de-risk.
    /// @param threatType The keccak256 threat category identifier.
    /// @param reason Human-readable threat description.
    /// @param duration Duration in seconds for the emergency state.
    event ThreatDetected(bytes32 indexed threatType, string reason, uint256 duration);

    /// @notice Emitted when a threat report is processed but does NOT trigger emergency.
    /// @param threatType The keccak256 threat category identifier.
    /// @param riskAdjustment The suggested risk score adjustment.
    event ThreatProcessed(bytes32 indexed threatType, uint256 riskAdjustment);

    // ──────────────────── Constants ────────────────────

    /// @notice Maximum allowed emergency duration (4 hours). HIGH-06 fix.
    uint256 public constant MAX_EMERGENCY_DURATION = 4 hours;

    /// @notice Minimum interval between emergency triggers (HIGH-NEW-04 fix).
    /// @dev Prevents a compromised W2 workflow from perpetually resetting the timer.
    uint256 public constant MIN_EMERGENCY_INTERVAL = 4 hours;

    // ──────────────────── State ────────────────────

    /// @notice Reference to the OszillorVault for typed interface calls.
    IOszillorVault public immutable vault;

    /// @notice Timestamp of the last emergency trigger (HIGH-NEW-04 fix).
    uint256 public lastEmergencyTrigger;

    /// @notice Constructs the EventSentinel with vault reference and CRE params.
    /// @param _vault Address of the OszillorVault contract.
    /// @param _forwarder CRE forwarder address.
    /// @param _workflowId CRE workflow CID.
    /// @param _workflowName CRE workflow name.
    /// @param _workflowOwner CRE workflow owner.
    constructor(
        address _vault,
        address _forwarder,
        bytes32 _workflowId,
        bytes10 _workflowName,
        address _workflowOwner
    ) CREReceiver(_forwarder, _workflowId, _workflowName, _workflowOwner) {
        vault = IOszillorVault(_vault);
    }

    /// @notice Processes a validated W2 threat report.
    /// @dev If `emergencyHalt` is true, calls vault.emergencyDeRisk() with a bounded
    ///      duration. Otherwise, only emits a monitoring event.
    /// @param report ABI-encoded ThreatReport struct.
    function _handleReport(bytes calldata report) internal override {
        ThreatReport memory threat = abi.decode(report, (ThreatReport));

        if (threat.emergencyHalt) {
            // HIGH-NEW-04 fix: Cooldown between emergency triggers
            if (block.timestamp < lastEmergencyTrigger + MIN_EMERGENCY_INTERVAL) {
                revert OszillorErrors.EmergencyTooFrequent(lastEmergencyTrigger + MIN_EMERGENCY_INTERVAL);
            }
            lastEmergencyTrigger = block.timestamp;

            // Bound the duration to MAX_EMERGENCY_DURATION (HIGH-06)
            uint256 duration = threat.suggestedDuration;
            if (duration > MAX_EMERGENCY_DURATION) {
                duration = MAX_EMERGENCY_DURATION;
            }
            if (duration == 0) {
                duration = 1 hours; // sensible default if CRE omits duration
            }

            // Trigger emergency de-risk via typed vault interface
            vault.emergencyDeRisk(threat.reason, duration);

            emit ThreatDetected(threat.threatType, threat.reason, duration);
        } else {
            // Non-emergency threat — just emit for monitoring
            emit ThreatProcessed(threat.threatType, threat.riskAdjustment);
        }
    }
}
