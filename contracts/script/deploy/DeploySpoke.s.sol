// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {OszillorTokenPool} from "../../src/core/OszillorTokenPool.sol";
import {SpokePeer} from "../../src/peers/SpokePeer.sol";
import {Roles} from "../../src/libraries/Roles.sol";

/// @title DeploySpoke
/// @author Hitesh (vyqno)
/// @notice Deploys spoke-chain contracts for the OSZILLOR protocol.
/// @dev Spoke deployment order (from plan.md Section 8):
///      1. OszillorToken (spoke instance, same code as hub)
///      2. OszillorTokenPool (spoke instance)
///      3. Grant RISK_MANAGER_ROLE on Token to TokenPool
///
///      NOTE: SpokePeer and HubPeer are Phase 08 contracts (not yet implemented).
///      This script deploys the token infrastructure needed for CCIP bridging.
///
///      Environment variables required:
///        DEPLOYER_PRIVATE_KEY  — deployer EOA
///        ADMIN_MULTISIG        — final admin address on spoke chain
///        CCIP_RMN_PROXY        — CCIP RMN proxy on spoke chain
///        CCIP_ROUTER           — CCIP Router on spoke chain
///        HUB_CHAIN_SELECTOR    — CCIP chain selector for the hub chain
///        HUB_TOKEN_POOL        — OszillorTokenPool address on hub chain
contract DeploySpoke is Script {
    OszillorToken public spokeToken;
    OszillorTokenPool public spokePool;
    SpokePeer public spokePeer;

    function run() external {
        address adminMultisig = vm.envAddress("ADMIN_MULTISIG");
        address rmnProxy = vm.envAddress("CCIP_RMN_PROXY");
        address ccipRouter = vm.envAddress("CCIP_ROUTER");

        vm.startBroadcast();

        // ─── Step 1: Deploy Spoke OszillorToken ───
        spokeToken = new OszillorToken("OSZILLOR", "OSZ", adminMultisig);
        console2.log("Spoke OszillorToken deployed at:", address(spokeToken));

        // ─── Step 2: Deploy Spoke OszillorTokenPool ───
        address[] memory allowlist = new address[](0);
        spokePool = new OszillorTokenPool(
            address(spokeToken),
            allowlist,
            rmnProxy,
            ccipRouter
        );
        console2.log("Spoke OszillorTokenPool deployed at:", address(spokePool));

        // ─── Step 3: Grant RISK_MANAGER_ROLE on Token to Pool ───
        spokeToken.grantRole(Roles.RISK_MANAGER_ROLE, address(spokePool));
        console2.log("Granted RISK_MANAGER_ROLE on Spoke Token to Spoke Pool");

        // ─── Step 4: Deploy SpokePeer ───
        uint64 hubChainSelector = uint64(vm.envUint("HUB_CHAIN_SELECTOR"));
        address feeTokenAddr = vm.envAddress("FEE_TOKEN");
        spokePeer = new SpokePeer(
            ccipRouter,
            feeTokenAddr,
            adminMultisig,
            adminMultisig, // feeRecipient = admin on spoke
            hubChainSelector
        );
        console2.log("SpokePeer deployed at:", address(spokePeer));

        vm.stopBroadcast();

        // ─── Summary ───
        console2.log("");
        console2.log("=== OSZILLOR Spoke Deployment Complete ===");
        console2.log("Spoke Token:    ", address(spokeToken));
        console2.log("Spoke Pool:     ", address(spokePool));
        console2.log("Spoke Peer:     ", address(spokePeer));
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("  1. Configure CCIP remote chain/pool on hub TokenPool");
        console2.log("  2. Configure CCIP remote chain/pool on spoke TokenPool");
        console2.log("  3. Register SpokePeer on HubPeer via registerSpoke()");
    }
}
