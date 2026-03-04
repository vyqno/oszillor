// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IRiskAdapter
/// @author Hitesh (vyqno)
/// @notice Interface for pluggable risk data sources.
/// @dev Adapters are registered in RiskRegistry and can be swapped without
///      redeploying core contracts. Not required for initial deployment — CRE
///      workflows handle data fetching off-chain. Designed for future extensibility
///      (e.g., DefiLlama, Chainlink Data Feeds, custom oracles).
interface IRiskAdapter {
    /// @notice Fetches risk data from the underlying source.
    /// @param params ABI-encoded parameters specific to the adapter implementation.
    /// @return data ABI-encoded risk data response.
    function fetchRiskData(bytes calldata params) external returns (bytes memory data);

    /// @notice Returns a human-readable name for this adapter.
    /// @return The adapter's identifier string (e.g., "defillama-tvl-monitor").
    function adapterName() external view returns (string memory);
}
