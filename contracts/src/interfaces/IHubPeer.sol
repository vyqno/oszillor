// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IOszillorPeer} from "./IOszillorPeer.sol";

/// @title IHubPeer
/// @author Hitesh (vyqno)
/// @notice Interface for the hub-chain CCIP peer.
/// @dev The hub is the canonical source of risk state. After every state change
///      (risk update, rebase, emergency), it broadcasts RiskStateSync to all
///      registered spokes via CCIP. Uses monotonically increasing nonces for
///      replay protection on spoke receivers.
interface IHubPeer is IOszillorPeer {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when risk state is broadcast to spokes.
    /// @param nonce Monotonic broadcast counter for replay protection.
    /// @param riskScore Current risk score at time of broadcast.
    /// @param rebaseIndex Current rebase index at time of broadcast.
    /// @param emergencyMode Whether emergency mode is active.
    /// @param spokeCount Number of spokes the broadcast was sent to.
    event RiskStateBroadcast(
        uint256 indexed nonce,
        uint256 riskScore,
        uint256 rebaseIndex,
        bool emergencyMode,
        uint256 spokeCount
    );

    /// @notice Emitted when a spoke chain is registered with the hub.
    /// @param chainSelector CCIP chain selector of the spoke.
    /// @param spokeAddress Address of the SpokePeer contract.
    event SpokeRegistered(uint64 indexed chainSelector, address spokeAddress);

    // ──────────────────── Mutative ────────────────────

    /// @notice Broadcasts the current risk state to all registered spokes via CCIP.
    /// @dev Public — anyone can trigger a broadcast and pay the CCIP fees.
    ///      Increments `currentNonce` monotonically.
    function broadcastRiskState() external payable;

    /// @notice Registers a spoke chain. Alias for registerPeer with spoke-specific validation.
    /// @dev Callable only by CROSS_CHAIN_ADMIN_ROLE.
    /// @param chainSelector CCIP chain selector of the spoke.
    /// @param spokeAddress Address of the SpokePeer contract on the spoke chain.
    function registerSpoke(uint64 chainSelector, address spokeAddress) external;

    // ──────────────────── View ────────────────────

    /// @notice Returns the current broadcast nonce.
    /// @return The latest nonce used in risk state broadcasts.
    function currentNonce() external view returns (uint256);

    /// @notice Returns all registered spoke chain selectors.
    /// @return Array of CCIP chain selectors for registered spokes.
    function getRegisteredSpokes() external view returns (uint64[] memory);
}
