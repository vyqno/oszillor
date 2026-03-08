// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";

import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {VaultStrategy} from "../../src/core/VaultStrategy.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {RebaseExecutor} from "../../src/modules/RebaseExecutor.sol";
import {EventSentinel} from "../../src/modules/EventSentinel.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskLevel} from "../../src/libraries/DataStructures.sol";

/// @title ValidateDeployment
/// @notice Post-deployment validation checklist for OSZILLOR v2.
/// @dev Run this script after DeployHub + SetupRoles to verify correctness.
///
/// Required env vars:
/// TOKEN_ADDRESS, VAULT_ADDRESS, STRATEGY_ADDRESS,
/// RISK_ENGINE_ADDRESS, REBASE_EXECUTOR_ADDRESS, EVENT_SENTINEL_ADDRESS,
/// TOKEN_POOL_ADDRESS, ADMIN_MULTISIG,
/// WETH_ADDRESS|WETH, USDC_ADDRESS|USDC,
/// UNISWAP_ROUTER, ETH_USD_FEED
contract ValidateDeployment is Script {
    struct Context {
        OszillorToken token;
        OszillorVault vault;
        VaultStrategy strategy;
        RiskEngine riskEngine;
        RebaseExecutor rebaseExecutor;
        EventSentinel eventSentinel;
        address tokenPool;
        address vaultAddr;
        address adminMultisig;
    }

    function run() external view {
        Context memory ctx = _loadContext();

        console2.log("=== OSZILLOR Post-Deployment Validation ===");
        console2.log("");

        _validateToken(ctx.token);
        _validateVault(ctx.vault, ctx.strategy);
        _validateStrategy(ctx.strategy, ctx.vaultAddr);
        _validateVaultRoles(ctx.vault, ctx.vaultAddr, address(ctx.riskEngine), address(ctx.rebaseExecutor), address(ctx.eventSentinel));
        _validateTokenRoles(ctx.token, ctx.vaultAddr, ctx.tokenPool);
        _validateCreReceivers(ctx.vaultAddr, ctx.riskEngine, ctx.rebaseExecutor, ctx.eventSentinel);
        _validateAdmin(ctx.token, ctx.vault, ctx.adminMultisig);

        console2.log("");
        console2.log("=== Validation Complete ===");
    }

    function _loadContext() internal view returns (Context memory ctx) {
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        ctx = Context({
            token: OszillorToken(vm.envAddress("TOKEN_ADDRESS")),
            vault: OszillorVault(vaultAddr),
            strategy: VaultStrategy(vm.envAddress("STRATEGY_ADDRESS")),
            riskEngine: RiskEngine(vm.envAddress("RISK_ENGINE_ADDRESS")),
            rebaseExecutor: RebaseExecutor(vm.envAddress("REBASE_EXECUTOR_ADDRESS")),
            eventSentinel: EventSentinel(vm.envAddress("EVENT_SENTINEL_ADDRESS")),
            tokenPool: vm.envAddress("TOKEN_POOL_ADDRESS"),
            vaultAddr: vaultAddr,
            adminMultisig: vm.envAddress("ADMIN_MULTISIG")
        });
    }

    function _validateToken(OszillorToken token) internal view {
        console2.log("[Token]");
        _check("Token name is OSZILLOR", keccak256(bytes(token.name())) == keccak256(bytes("OSZILLOR")));
        _check("Token symbol is OSZ", keccak256(bytes(token.symbol())) == keccak256(bytes("OSZ")));
        _check("Initial rebaseIndex is 1e18", token.rebaseIndex() == 1e18);
        _check("Initial totalShares is 10000 (virtual offset)", token.totalShares() == 1e22);
        _check("Initial epoch is 0", token.epoch() == 0);
    }

    function _validateVault(OszillorVault vault, VaultStrategy strategy) internal view {
        console2.log("");
        console2.log("[Vault]");
        _check("Risk state initialized to CAUTION (score=50)", vault.currentRiskScore() == 50);
        _check("Risk level is CAUTION", vault.riskLevel() == RiskLevel.CAUTION);
        _check("No emergency mode", !vault.emergencyMode());
        _check("Vault asset is WETH", address(vault.asset()) == _envAddressEither("WETH_ADDRESS", "WETH"));
        _check("Vault strategy points to STRATEGY_ADDRESS", address(vault.strategy()) == address(strategy));
        _check("internalTotalAssets is 0.01 WETH (virtual offset)", vault.internalTotalAssets() == 1e16);
        _check("Fee rate is 50 bps (0.5%)", vault.feeRateBps() == 50);
        _check("Accrued fees is 0", vault.accruedFees() == 0);
    }

    function _validateStrategy(VaultStrategy strategy, address vaultAddr) internal view {
        console2.log("");
        console2.log("[Strategy]");
        _check("Strategy has STRATEGY_MANAGER_ROLE for Vault", strategy.hasRole(Roles.STRATEGY_MANAGER_ROLE, vaultAddr));
        _check("Strategy WETH address is correct", address(strategy.weth()) == _envAddressEither("WETH_ADDRESS", "WETH"));
        _check("Strategy USDC address is correct", address(strategy.usdc()) == _envAddressEither("USDC_ADDRESS", "USDC"));
        _check("Strategy router is correct", address(strategy.uniRouter()) == vm.envAddress("UNISWAP_ROUTER"));
        _check("Strategy ETH/USD feed is correct", address(strategy.ethUsdFeed()) == vm.envAddress("ETH_USD_FEED"));
        _check("Strategy Lido address is non-zero", address(strategy.lido()) != address(0));
    }

    function _validateVaultRoles(
        OszillorVault vault,
        address vaultAddr,
        address riskEngineAddr,
        address rebaseExecutorAddr,
        address eventSentinelAddr
    ) internal view {
        console2.log("");
        console2.log("[Vault Roles]");
        _check("RiskEngine has RISK_MANAGER_ROLE on Vault", vault.hasRole(Roles.RISK_MANAGER_ROLE, riskEngineAddr));
        _check("Vault self has RISK_MANAGER_ROLE", vault.hasRole(Roles.RISK_MANAGER_ROLE, vaultAddr));
        _check("RebaseExecutor has REBASE_EXECUTOR_ROLE on Vault", vault.hasRole(Roles.REBASE_EXECUTOR_ROLE, rebaseExecutorAddr));
        _check("EventSentinel has SENTINEL_ROLE on Vault", vault.hasRole(Roles.SENTINEL_ROLE, eventSentinelAddr));
    }

    function _validateTokenRoles(OszillorToken token, address vaultAddr, address tokenPoolAddr) internal view {
        console2.log("");
        console2.log("[Token Roles]");
        _check("Vault has RISK_MANAGER_ROLE on Token", token.hasRole(Roles.RISK_MANAGER_ROLE, vaultAddr));
        _check("Vault has REBASE_EXECUTOR_ROLE on Token", token.hasRole(Roles.REBASE_EXECUTOR_ROLE, vaultAddr));
        _check("TokenPool has RISK_MANAGER_ROLE on Token", token.hasRole(Roles.RISK_MANAGER_ROLE, tokenPoolAddr));
    }

    function _validateCreReceivers(
        address vaultAddr,
        RiskEngine riskEngine,
        RebaseExecutor rebaseExecutor,
        EventSentinel eventSentinel
    ) internal view {
        console2.log("");
        console2.log("[CRE Receivers]");
        _check("RiskEngine vault points to correct vault", address(riskEngine.vault()) == vaultAddr);
        _check("RebaseExecutor vault points to correct vault", address(rebaseExecutor.vault()) == vaultAddr);
        _check("EventSentinel vault points to correct vault", address(eventSentinel.vault()) == vaultAddr);
        _check(
            "All CRE receivers share same forwarder",
            riskEngine.FORWARDER() == rebaseExecutor.FORWARDER() && rebaseExecutor.FORWARDER() == eventSentinel.FORWARDER()
        );
    }

    function _validateAdmin(OszillorToken token, OszillorVault vault, address adminMultisig) internal view {
        console2.log("");
        console2.log("[Admin Security]");
        _check("Admin multisig is DEFAULT_ADMIN on Vault", vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), adminMultisig));
        _check("Admin multisig is DEFAULT_ADMIN on Token", token.hasRole(token.DEFAULT_ADMIN_ROLE(), adminMultisig));
    }

    function _check(string memory label, bool condition) internal pure {
        if (condition) {
            console2.log("  [OK]", label);
        } else {
            console2.log("  [FAIL]", label);
            revert(string.concat("Validation failed: ", label));
        }
    }

    function _envAddressEither(string memory primaryKey, string memory fallbackKey) internal view returns (address value) {
        value = vm.envOr(primaryKey, address(0));
        if (value == address(0)) {
            value = vm.envOr(fallbackKey, address(0));
        }
        require(value != address(0), string.concat("Missing env address: ", primaryKey));
    }
}
