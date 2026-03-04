// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";

/// @title RiskRegistry
/// @author Hitesh (vyqno)
/// @notice Registry of IRiskAdapter implementations for extensible risk data sources.
/// @dev Maps `bytes32 protocolId` to adapter addresses. Follows YieldCoin's
///      StrategyRegistry pattern with Ownable2Step for safe admin transfers.
///      Not required for initial deployment — CRE workflows handle data fetching
///      off-chain. Designed for future extensibility.
contract RiskRegistry is Ownable2Step {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when an adapter is registered or updated.
    /// @param protocolId The protocol identifier.
    /// @param adapter Address of the adapter contract.
    event AdapterRegistered(bytes32 indexed protocolId, address adapter);

    /// @notice Emitted when an adapter is removed.
    /// @param protocolId The protocol identifier that was removed.
    event AdapterRemoved(bytes32 indexed protocolId);

    // ──────────────────── State ────────────────────

    /// @notice Maps protocol identifier to adapter contract address.
    mapping(bytes32 => address) public adapters;

    /// @notice Array of all registered protocol IDs for enumeration.
    bytes32[] public protocolIds;

    /// @notice Constructs the registry with the given admin.
    /// @param admin Address receiving ownership (should be multisig).
    constructor(address admin) Ownable(admin) {}

    // ──────────────────── Mutative ────────────────────

    /// @notice Registers or updates an adapter for a protocol.
    /// @dev Callable only by owner. Zero-address adapter is not allowed.
    /// @param protocolId The bytes32 protocol identifier (e.g., keccak256("aave-v3")).
    /// @param adapter Address of the IRiskAdapter implementation.
    function registerAdapter(bytes32 protocolId, address adapter) external onlyOwner {
        if (adapter == address(0)) revert OszillorErrors.ZeroAddress();

        if (adapters[protocolId] == address(0)) {
            // New registration — add to enumeration array
            protocolIds.push(protocolId);
        }

        adapters[protocolId] = adapter;
        emit AdapterRegistered(protocolId, adapter);
    }

    /// @notice Removes an adapter registration.
    /// @dev Callable only by owner. Does NOT remove from protocolIds array
    ///      (would be gas-expensive with swaps). Adapter check returns address(0).
    /// @param protocolId The protocol identifier to remove.
    function removeAdapter(bytes32 protocolId) external onlyOwner {
        if (adapters[protocolId] == address(0)) revert OszillorErrors.ZeroAddress();
        delete adapters[protocolId];
        emit AdapterRemoved(protocolId);
    }

    // ──────────────────── View ────────────────────

    /// @notice Returns the adapter address for a protocol.
    /// @param protocolId The protocol identifier.
    /// @return The adapter contract address (address(0) if not registered).
    function getAdapter(bytes32 protocolId) external view returns (address) {
        return adapters[protocolId];
    }

    /// @notice Returns the total number of registered protocol IDs.
    /// @dev Note: some may have been removed (adapter == address(0)).
    function registeredCount() external view returns (uint256) {
        return protocolIds.length;
    }
}
