// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {OszillorTokenPool} from "../../src/core/OszillorTokenPool.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {RebaseExecutor} from "../../src/modules/RebaseExecutor.sol";
import {EventSentinel} from "../../src/modules/EventSentinel.sol";
import {HubPeer} from "../../src/peers/HubPeer.sol";
import {VaultStrategy} from "../../src/core/VaultStrategy.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {MockLido} from "../../test/mocks/MockLido.sol";

/// @title DeployHub
/// @author Hitesh (vyqno)
/// @notice Deploys all hub-chain contracts for the OSZILLOR protocol.
/// @dev See plan.md Section 8 for deployment order and rationale.
contract DeployHub is Script {
    struct CREConfig {
        address forwarder;
        bytes32 workflowId;
        bytes10 workflowName;
        address workflowOwner;
    }

    // Deployed contract references (accessible after run())
    OszillorToken public token;
    RiskEngine public riskEngine;
    RebaseExecutor public rebaseExecutor;
    EventSentinel public eventSentinel;
    VaultStrategy public strategy;
    OszillorVault public vault;
    OszillorTokenPool public tokenPool;
    HubPeer public hubPeer;
    MockLido public mockLido;

    function run() external {
        // Core addresses
        address weth = _envAddressEither("WETH_ADDRESS", "WETH");
        address usdc = _envAddressEither("USDC_ADDRESS", "USDC");
        address admin = vm.envAddress("ADMIN_MULTISIG");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address creForwarder = vm.envAddress("CRE_FORWARDER");
        address uniRouter = vm.envAddress("UNISWAP_ROUTER");
        address ethUsdFeed = vm.envAddress("ETH_USD_FEED");
        bool deployMockLido = vm.envOr("DEPLOY_MOCK_LIDO", false);
        address lidoSteth = vm.envOr("LIDO_STETH", address(0));

        vm.startBroadcast();

        // Step 1: Token
        token = new OszillorToken("OSZILLOR", "OSZ", admin);
        console2.log("Token:", address(token));

        // Optional Step: Sepolia MockLido when no stETH deployment exists
        if (deployMockLido || lidoSteth == address(0)) {
            mockLido = new MockLido(weth);
            lidoSteth = address(mockLido);
            console2.log("MockLido:", lidoSteth);
        }

        // Predict vault address (deployed 4 CREATE ops later: strategy + 3 CRE modules).
        // Use explicit deployer env address so simulation + broadcast stay deterministic.
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address predictedVault = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 4);

        // Step 2: VaultStrategy (NEW for v2)
        strategy = new VaultStrategy(weth, usdc, lidoSteth, uniRouter, ethUsdFeed, admin);
        console2.log("VaultStrategy:", address(strategy));

        // Step 3: RiskEngine (W1)
        riskEngine = _deployRiskEngine(predictedVault, creForwarder);

        // Step 4: RebaseExecutor (W3)
        rebaseExecutor = _deployRebaseExecutor(predictedVault, creForwarder);

        // Step 5: EventSentinel (W2)
        eventSentinel = _deployEventSentinel(predictedVault, creForwarder);

        // Step 6: Vault (v2 — WETH base asset, strategy integration)
        vault = new OszillorVault(
            weth, address(token), address(riskEngine),
            address(rebaseExecutor), address(eventSentinel),
            address(strategy), admin, feeRecipient
        );
        require(address(vault) == predictedVault, "Vault address prediction failed!");
        console2.log("Vault:", address(vault));

        // Step 7: Grant roles on Token to Vault
        token.grantRole(Roles.RISK_MANAGER_ROLE, address(vault));
        token.grantRole(Roles.REBASE_EXECUTOR_ROLE, address(vault));
        token.grantRole(Roles.TOKEN_MINTER_ROLE, address(vault));

        // Step 8: Grant STRATEGY_MANAGER_ROLE on Strategy to Vault
        strategy.grantRole(Roles.STRATEGY_MANAGER_ROLE, address(vault));

        // Step 8: TokenPool (CCIP)
        tokenPool = _deployTokenPool(creForwarder);

        // Grant RISK_MANAGER_ROLE on Token to TokenPool
        token.grantRole(Roles.RISK_MANAGER_ROLE, address(tokenPool));

        // Step 9: HubPeer (CCIP cross-chain messaging)
        address feeTokenAddr = vm.envAddress("FEE_TOKEN");
        hubPeer = new HubPeer(
            vm.envAddress("CCIP_ROUTER"),
            feeTokenAddr,
            admin,
            feeRecipient,
            address(vault),
            address(token)
        );
        console2.log("HubPeer:", address(hubPeer));

        vm.stopBroadcast();

        _printSummary();
    }

    function _deployRiskEngine(address predictedVault, address creForwarder) internal returns (RiskEngine) {
        CREConfig memory cfg = _loadCREConfig("W1");
        RiskEngine re = new RiskEngine(
            predictedVault, predictedVault, creForwarder,
            cfg.workflowId, cfg.workflowName, cfg.workflowOwner
        );
        console2.log("RiskEngine:", address(re));
        return re;
    }

    function _deployRebaseExecutor(address predictedVault, address creForwarder) internal returns (RebaseExecutor) {
        CREConfig memory cfg = _loadCREConfig("W3");
        RebaseExecutor re = new RebaseExecutor(
            predictedVault, predictedVault, creForwarder,
            cfg.workflowId, cfg.workflowName, cfg.workflowOwner
        );
        console2.log("RebaseExecutor:", address(re));
        return re;
    }

    function _deployEventSentinel(address predictedVault, address creForwarder) internal returns (EventSentinel) {
        CREConfig memory cfg = _loadCREConfig("W2");
        EventSentinel es = new EventSentinel(
            predictedVault, creForwarder,
            cfg.workflowId, cfg.workflowName, cfg.workflowOwner
        );
        console2.log("EventSentinel:", address(es));
        return es;
    }

    function _deployTokenPool(address) internal returns (OszillorTokenPool) {
        address rmnProxy = vm.envAddress("CCIP_RMN_PROXY");
        address ccipRouter = vm.envAddress("CCIP_ROUTER");
        address[] memory allowlist = new address[](0);
        OszillorTokenPool pool = new OszillorTokenPool(
            address(token), allowlist, rmnProxy, ccipRouter
        );
        console2.log("TokenPool:", address(pool));
        return pool;
    }

    function _loadCREConfig(string memory prefix) internal returns (CREConfig memory cfg) {
        cfg.workflowId = vm.envBytes32(string.concat(prefix, "_WORKFLOW_ID"));
        cfg.workflowName = bytes10(vm.envBytes32(string.concat(prefix, "_WORKFLOW_NAME")));
        cfg.workflowOwner = vm.envAddress(string.concat(prefix, "_WORKFLOW_OWNER"));
    }

    function _printSummary() internal view {
        console2.log("");
        console2.log("=== OSZILLOR Hub Deployment Complete ===");
        console2.log("Token:         ", address(token));
        if (address(mockLido) != address(0)) {
            console2.log("MockLido:      ", address(mockLido));
        }
        console2.log("RiskEngine:    ", address(riskEngine));
        console2.log("RebaseExecutor:", address(rebaseExecutor));
        console2.log("EventSentinel: ", address(eventSentinel));
        console2.log("Vault:         ", address(vault));
        console2.log("TokenPool:     ", address(tokenPool));
        console2.log("HubPeer:       ", address(hubPeer));
        console2.log("");
        console2.log("NEXT: Run SetupRoles.s.sol to assign operational roles.");
    }

    function _envAddressEither(string memory primaryKey, string memory fallbackKey) internal view returns (address value) {
        value = vm.envOr(primaryKey, address(0));
        if (value == address(0)) {
            value = vm.envOr(fallbackKey, address(0));
        }
        require(value != address(0), string.concat("Missing env address: ", primaryKey));
    }
}
