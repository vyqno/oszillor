// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IOszillorPeer} from "./IOszillorPeer.sol";
import {RiskLevel} from "../libraries/DataStructures.sol";

/// @title ISpokePeer
/// @author Hitesh (vyqno)
/// @notice Interface for spoke-chain CCIP peers.
/// @dev Spokes are thin mirrors of hub state. They receive RiskStateSync messages
///      via CCIP and apply them locally. Includes nonce-based replay protection
///      (MED-02), timestamp staleness checks (MED-02), and index divergence
///      validation (MED-01). Reverts on unknown message types (MED-08).
interface ISpokePeer is IOszillorPeer {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a risk state sync is received and applied from hub.
    /// @param nonce The nonce from the hub broadcast.
    /// @param riskScore Updated risk score.
    /// @param rebaseIndex Updated rebase index.
    /// @param emergencyMode Whether emergency mode is active on hub.
    event RiskStateSynced(
        uint256 indexed nonce,
        uint256 riskScore,
        uint256 rebaseIndex,
        bool emergencyMode
    );

    /// @notice Emitted when the spoke enters stale state (>15 min without hub update).
    /// @param lastUpdate Timestamp of the last hub update.
    /// @param staleDuration How long the spoke has been without an update.
    event SpokeStateStale(uint256 lastUpdate, uint256 staleDuration);

    // ──────────────────── View ────────────────────

    /// @notice Returns the timestamp of the last hub update received via CCIP.
    /// @return Unix timestamp of the most recent RiskStateSync application.
    function lastHubUpdate() external view returns (uint256);

    /// @notice Returns the last processed nonce from the hub chain.
    /// @return The highest nonce value accepted from hub broadcasts.
    function lastProcessedNonce() external view returns (uint256);

    /// @notice Returns the hub's last broadcast rebase index for divergence checks.
    /// @return The rebaseIndex from the most recent RiskStateSync.
    function lastReceivedRebaseIndex() external view returns (uint256);

    /// @notice Returns the hub chain selector this spoke is linked to.
    /// @return CCIP chain selector of the hub chain.
    function hubChainSelector() external view returns (uint64);

    /// @notice Returns the maximum staleness before deposits are blocked.
    /// @return Duration in seconds (default: 15 minutes).
    function maxSpokeStaleness() external view returns (uint256);

    /// @notice Returns the maximum allowed index divergence before withdrawals are blocked.
    /// @return Divergence threshold in basis points (default: 500 = 5%).
    function maxIndexDivergenceBps() external view returns (uint256);

    /// @notice Checks whether the spoke's state is considered stale.
    /// @return True if time since last hub update exceeds maxSpokeStaleness.
    function isStateStale() external view returns (bool);

    /// @notice Returns the current risk level on this spoke (derived from synced state).
    /// @return The risk level tier.
    function spokeRiskLevel() external view returns (RiskLevel);
}
