// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IOszillorPeer
/// @author Hitesh (vyqno)
/// @notice Base interface for CCIP peer contracts (hub and spoke).
/// @dev Provides chain registration, gas limit management, and peer address queries.
///      Both HubPeer and SpokePeer extend this interface.
interface IOszillorPeer {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a new peer chain is registered or updated.
    /// @param chainSelector CCIP chain selector for the remote chain.
    /// @param peerAddress Address of the peer contract on the remote chain.
    event PeerRegistered(uint64 indexed chainSelector, address peerAddress);

    /// @notice Emitted when a peer chain is removed.
    /// @param chainSelector CCIP chain selector of the removed chain.
    event PeerRemoved(uint64 indexed chainSelector);

    /// @notice Emitted when the gas limit for a message type is updated.
    /// @param messageType Identifier for the CCIP message type.
    /// @param newGasLimit The new gas limit value.
    event GasLimitUpdated(uint8 indexed messageType, uint256 newGasLimit);

    // ──────────────────── Mutative ────────────────────

    /// @notice Registers or updates a peer contract on a remote chain.
    /// @dev Callable only by CROSS_CHAIN_ADMIN_ROLE.
    /// @param chainSelector CCIP chain selector for the remote chain.
    /// @param peerAddress Address of the peer contract on the remote chain.
    function registerPeer(uint64 chainSelector, address peerAddress) external;

    /// @notice Removes a registered peer chain.
    /// @dev Callable only by CROSS_CHAIN_ADMIN_ROLE.
    /// @param chainSelector CCIP chain selector to remove.
    function removePeer(uint64 chainSelector) external;

    /// @notice Updates the gas limit for a specific CCIP message type.
    /// @dev Callable only by CROSS_CHAIN_ADMIN_ROLE.
    /// @param messageType Identifier for the CCIP message type.
    /// @param gasLimit New gas limit value.
    function setGasLimit(uint8 messageType, uint256 gasLimit) external;

    // ──────────────────── View ────────────────────

    /// @notice Returns the peer address registered for a given chain.
    /// @param chainSelector CCIP chain selector.
    /// @return The peer contract address (address(0) if not registered).
    function getPeer(uint64 chainSelector) external view returns (address);

    /// @notice Checks whether a chain selector has a registered peer.
    /// @param chainSelector CCIP chain selector.
    /// @return True if the chain has a registered peer.
    function isPeerRegistered(uint64 chainSelector) external view returns (bool);

    /// @notice Returns the gas limit configured for a CCIP message type.
    /// @param messageType Identifier for the CCIP message type.
    /// @return The configured gas limit.
    function getGasLimit(uint8 messageType) external view returns (uint256);
}
