// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Roles
/// @author Hitesh (vyqno)
/// @notice Centralized role constants for the OSZILLOR protocol.
/// @dev All role-based access is governed by AccessControlDefaultAdminRules.
///      No other contract should define role bytes32 constants — import from here.
library Roles {
    /// @notice Manages protocol configuration (risk adapters, registry settings).
    bytes32 internal constant CONFIG_ADMIN_ROLE = keccak256("CONFIG_ADMIN_ROLE");

    /// @notice Manages CCIP spoke registration and cross-chain gas limits.
    bytes32 internal constant CROSS_CHAIN_ADMIN_ROLE = keccak256("CROSS_CHAIN_ADMIN_ROLE");

    /// @notice Granted to RiskEngine and Vault for share mint/burn operations.
    bytes32 internal constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    /// @notice Granted to RebaseExecutor contract — sole authority to trigger rebases.
    bytes32 internal constant REBASE_EXECUTOR_ROLE = keccak256("REBASE_EXECUTOR_ROLE");

    /// @notice Granted to EventSentinel contract — triggers emergency de-risk.
    bytes32 internal constant SENTINEL_ROLE = keccak256("SENTINEL_ROLE");

    /// @notice Dedicated hot wallet for rapid emergency pause.
    bytes32 internal constant EMERGENCY_PAUSER_ROLE = keccak256("EMERGENCY_PAUSER_ROLE");

    /// @notice Separate address from pauser to prevent hostage scenarios.
    bytes32 internal constant EMERGENCY_UNPAUSER_ROLE = keccak256("EMERGENCY_UNPAUSER_ROLE");

    /// @notice Governance / multisig — can adjust the streaming fee rate.
    bytes32 internal constant FEE_RATE_SETTER_ROLE = keccak256("FEE_RATE_SETTER_ROLE");

    /// @notice Treasury multisig — can withdraw accrued protocol fees.
    bytes32 internal constant FEE_WITHDRAWER_ROLE = keccak256("FEE_WITHDRAWER_ROLE");

    /// @notice Granted to OszillorVault — sole authority to call VaultStrategy.rebalance().
    bytes32 internal constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");

    /// @notice Granted to OszillorVault — authority to mint/burn shares on OszillorToken.
    /// @dev Separated from RISK_MANAGER_ROLE (HIGH-NEW-01 fix) so the vault does not
    ///      hold RISK_MANAGER_ROLE on itself, preventing bypass of RiskEngine checks.
    bytes32 internal constant TOKEN_MINTER_ROLE = keccak256("TOKEN_MINTER_ROLE");
}
