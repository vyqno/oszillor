// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {AlertRegistry} from "../../src/modules/AlertRegistry.sol";

/// @title DeployAlertRegistry
/// @author Hitesh (vyqno)
/// @notice Deploys AlertRegistry to Base Sepolia for CRE W4 alert subscriptions.
/// @dev AlertRegistry is the ONLY contract on Base Sepolia. It receives alert
///      subscriptions from the CRE W4 HTTP trigger (originating from the x402 Risk API).
///      The CRE W4 cron trigger reads active rules via view functions.
///
///      Environment variables required:
///        DEPLOYER_ADDRESS              — deployer EOA address
///        ADMIN_MULTISIG                — contract owner (can withdraw USDC revenue)
///        BASE_USDC                     — USDC token address on Base Sepolia
///        BASE_CRE_FORWARDER            — KeystoneForwarder on Base Sepolia
///        W4_WORKFLOW_ID                — CRE W4 workflow CID (bytes32)
///        W4_WORKFLOW_NAME              — CRE W4 workflow name (bytes10)
///        W4_WORKFLOW_OWNER             — CRE W4 workflow owner address
contract DeployAlertRegistry is Script {
    AlertRegistry public alertRegistry;

    function run() external {
        address admin = vm.envAddress("ADMIN_MULTISIG");
        address usdc = vm.envAddress("BASE_USDC");
        address creForwarder = vm.envAddress("BASE_CRE_FORWARDER");

        // W4 CRE validation params
        bytes32 workflowId = vm.envBytes32("W4_WORKFLOW_ID");
        bytes10 workflowName = bytes10(vm.envBytes32("W4_WORKFLOW_NAME"));
        address workflowOwner = vm.envAddress("W4_WORKFLOW_OWNER");

        vm.startBroadcast();

        alertRegistry = new AlertRegistry(
            usdc,
            admin,
            creForwarder,
            workflowId,
            workflowName,
            workflowOwner
        );

        vm.stopBroadcast();

        console2.log("");
        console2.log("=== AlertRegistry Deployment (Base Sepolia) ===");
        console2.log("AlertRegistry:", address(alertRegistry));
        console2.log("Owner:        ", admin);
        console2.log("USDC:         ", usdc);
        console2.log("CRE Forwarder:", creForwarder);
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("  1. Update contracts/.env with ALERT_REGISTRY_ADDRESS=", address(alertRegistry));
        console2.log("  2. Update cre-workflows/oszillor-risk-alerts/config.staging.json");
        console2.log("     with the AlertRegistry address");
        console2.log("  3. Update risk-api/.env with ALERT_REGISTRY_ADDRESS if needed");
    }
}
