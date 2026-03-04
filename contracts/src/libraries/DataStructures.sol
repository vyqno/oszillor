// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title DataStructures
/// @author Hitesh (vyqno)
/// @notice Shared enums and structs used across the OSZILLOR protocol.
/// @dev Imported by interfaces, modules, and core contracts. Never holds state.

/// @notice Risk tier classification derived from a 0-100 risk score.
/// @dev SAFE=0-39, CAUTION=40-69, DANGER=70-89, CRITICAL=90-100.
enum RiskLevel {
    SAFE,
    CAUTION,
    DANGER,
    CRITICAL
}

/// @notice On-chain risk state written by RiskEngine via CRE W1.
/// @param riskScore Normalized risk score (0 = no risk, 100 = maximum risk).
/// @param confidence CRE DON consensus confidence (0-100). Reports below 60 are rejected.
/// @param timestamp Block timestamp of the last accepted risk update.
/// @param reasoningHash keccak256 of the AI reasoning output — provides an audit trail.
struct RiskState {
    uint256 riskScore;
    uint256 confidence;
    uint256 timestamp;
    bytes32 reasoningHash;
}

/// @notice A single yield-source allocation tracked by the vault.
/// @param protocol Human-readable protocol identifier (e.g. "aave-v3-usdc").
/// @param percentageBps Allocation weight in basis points (100 = 1%).
/// @param apyBps Current APY of this source in basis points.
struct Allocation {
    string protocol;
    uint256 percentageBps;
    uint256 apyBps;
}

/// @notice Snapshot of a single rebase event.
/// @param factor Multiplicative factor applied to rebaseIndex (1e18 precision).
/// @param epoch Monotonically increasing rebase counter.
/// @param timestamp Block timestamp when the rebase executed.
struct RebaseData {
    uint256 factor;
    uint256 epoch;
    uint256 timestamp;
}

/// @notice CCIP hub-to-spoke state synchronization message.
/// @param riskScore Current hub risk score.
/// @param rebaseIndex Current hub rebaseIndex (1e18 precision).
/// @param emergencyMode Whether the hub is in emergency mode.
/// @param timestamp Hub-side timestamp for staleness detection.
/// @param nonce Monotonic counter for replay protection.
struct RiskStateSync {
    uint256 riskScore;
    uint256 rebaseIndex;
    bool emergencyMode;
    uint256 timestamp;
    uint256 nonce;
}

/// @notice CRE W1 report payload decoded from the DON consensus output.
/// @param riskScore Assessed risk score (0-100).
/// @param confidence DON consensus confidence (0-100).
/// @param reasoningHash keccak256 of the AI reasoning string.
/// @param allocations Updated yield-source allocations.
struct RiskReport {
    uint256 riskScore;
    uint256 confidence;
    bytes32 reasoningHash;
    Allocation[] allocations;
}

/// @notice CRE W2 threat report from EventSentinel.
/// @param level Classified threat severity.
/// @param threatType keccak256 identifier of the threat category.
/// @param riskAdjustment Suggested additive risk score adjustment.
/// @param emergencyHalt Whether to trigger emergency de-risk immediately.
/// @param suggestedDuration Seconds the emergency state should last (capped at 4 hours).
/// @param reason Human-readable threat description.
struct ThreatReport {
    RiskLevel level;
    bytes32 threatType;
    uint256 riskAdjustment;
    bool emergencyHalt;
    uint256 suggestedDuration;
    string reason;
}

/// @notice CRE W3 rebase execution report.
/// @param rebaseFactor Multiplicative factor to apply (1e18 precision).
/// @param currentRiskScore Risk score at time of calculation.
/// @param weightedApyBps Weighted APY across all allocations in basis points.
/// @param timeDelta Seconds elapsed since last rebase.
struct RebaseReport {
    uint256 rebaseFactor;
    uint256 currentRiskScore;
    uint256 weightedApyBps;
    uint256 timeDelta;
}

/// @notice CCIP message type identifier for hub-spoke communication.
/// @dev Used to route incoming CCIP messages to the correct handler.
enum CcipMessageType {
    RISK_STATE_SYNC,
    DEPOSIT_FORWARD,
    WITHDRAWAL_FORWARD,
    REBALANCE
}
