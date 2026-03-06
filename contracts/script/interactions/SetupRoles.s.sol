// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/// @title SetupRoles
/// @author Hitesh (vyqno)
/// @notice Post-deployment role configuration for the OSZILLOR protocol.
/// @dev Run AFTER DeployHub.s.sol. Assigns operational roles to the correct addresses.
///      This script DOES NOT transfer DEFAULT_ADMIN_ROLE — that requires a 5-day delay
///      and must be initiated separately via the AccessControlDefaultAdminRules flow.
///
///      Environment variables required:
///        DEPLOYER_PRIVATE_KEY      — deployer EOA (via --account flag or --private-key)
///        VAULT_ADDRESS             — deployed OszillorVault address
///        TOKEN_ADDRESS             — deployed OszillorToken address
///        EMERGENCY_PAUSER          — hot wallet for rapid emergency response
///        EMERGENCY_UNPAUSER        — separate address for unpausing (never same as pauser!)
///        FEE_RATE_SETTER           — governance/multisig for fee rate changes
///        FEE_WITHDRAWER            — treasury multisig for fee withdrawal
///        CONFIG_ADMIN              — config admin for risk adapter registry
///        CROSS_CHAIN_ADMIN         — admin for CCIP spoke registration
contract SetupRoles is Script {
    function run() external {
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        // Role addresses
        address emergencyPauser = vm.envAddress("EMERGENCY_PAUSER");
        address emergencyUnpauser = vm.envAddress("EMERGENCY_UNPAUSER");
        address feeRateSetter = vm.envAddress("FEE_RATE_SETTER");
        address feeWithdrawer = vm.envAddress("FEE_WITHDRAWER");
        address configAdmin = vm.envAddress("CONFIG_ADMIN");
        address crossChainAdmin = vm.envAddress("CROSS_CHAIN_ADMIN");

        // Safety: pauser and unpauser MUST be different addresses
        require(emergencyPauser != emergencyUnpauser, "Pauser and Unpauser must be different!");
        require(emergencyPauser != address(0), "Pauser cannot be zero address");
        require(emergencyUnpauser != address(0), "Unpauser cannot be zero address");

        OszillorVault vault = OszillorVault(vaultAddr);
        // Token roles (RISK_MANAGER, REBASE_EXECUTOR) were set in DeployHub.s.sol

        vm.startBroadcast();

        // ─── Vault Roles ───

        // Emergency Pauser (hot wallet for rapid response)
        vault.grantRole(Roles.EMERGENCY_PAUSER_ROLE, emergencyPauser);
        console2.log("Granted EMERGENCY_PAUSER_ROLE to:", emergencyPauser);

        // Emergency Unpauser (DIFFERENT address — prevents hostage)
        vault.grantRole(Roles.EMERGENCY_UNPAUSER_ROLE, emergencyUnpauser);
        console2.log("Granted EMERGENCY_UNPAUSER_ROLE to:", emergencyUnpauser);

        // Fee Rate Setter (governance/multisig)
        vault.grantRole(Roles.FEE_RATE_SETTER_ROLE, feeRateSetter);
        console2.log("Granted FEE_RATE_SETTER_ROLE to:", feeRateSetter);

        // Fee Withdrawer (treasury multisig)
        vault.grantRole(Roles.FEE_WITHDRAWER_ROLE, feeWithdrawer);
        console2.log("Granted FEE_WITHDRAWER_ROLE to:", feeWithdrawer);

        // Config Admin (risk adapter management)
        vault.grantRole(Roles.CONFIG_ADMIN_ROLE, configAdmin);
        console2.log("Granted CONFIG_ADMIN_ROLE to:", configAdmin);

        // Cross-Chain Admin (CCIP spoke registration)
        vault.grantRole(Roles.CROSS_CHAIN_ADMIN_ROLE, crossChainAdmin);
        console2.log("Granted CROSS_CHAIN_ADMIN_ROLE to:", crossChainAdmin);

        vm.stopBroadcast();

        // ─── Validation Summary ───
        console2.log("");
        console2.log("=== Role Setup Complete ===");
        console2.log("");
        console2.log("CRITICAL NEXT STEPS:");
        console2.log("  1. Initiate DEFAULT_ADMIN_ROLE transfer to multisig (5-day delay)");
        console2.log("     vault.beginDefaultAdminTransfer(multisig)");
        console2.log("     token.beginDefaultAdminTransfer(multisig)");
        console2.log("  2. After 5 days: multisig calls acceptDefaultAdminTransfer()");
        console2.log("  3. Deployer EOA renounces all roles");
        console2.log("  4. Verify all roles are on correct addresses (not deployer)");
    }
}
