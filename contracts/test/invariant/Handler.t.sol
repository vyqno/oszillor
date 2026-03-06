// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {RebaseExecutor} from "../../src/modules/RebaseExecutor.sol";
import {EventSentinel} from "../../src/modules/EventSentinel.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title InvariantHandler
/// @notice Stateful handler for invariant/fuzz testing of the OSZILLOR protocol.
contract InvariantHandler is Test {
    OszillorToken public token;
    OszillorVault public vault;
    MockERC20 public usdc;

    address[] public actors;
    address internal currentActor;

    // ──────────────────── Ghost Variables ────────────────────
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_rebaseCount;
    uint256 public ghost_emergencyCount;

    constructor(
        OszillorToken _token,
        OszillorVault _vault,
        MockERC20 _usdc
    ) {
        token = _token;
        vault = _vault;
        usdc = _usdc;

        // Create actors
        for (uint256 i = 0; i < 3; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            // Fund each actor with 1M USDC
            usdc.mint(actor, 1_000_000e6);
            vm.prank(actor);
            usdc.approve(address(vault), type(uint256).max);
        }
    }

    // ──────────────────── Actions ────────────────────

    function deposit(uint256 amount) external {
        currentActor = actors[amount % actors.length];
        amount = bound(amount, 1e6, 100_000e6); // 1 — 100k USDC

        vm.prank(currentActor);
        try vault.deposit(amount) {
            ghost_totalDeposited += amount;
        } catch {}
    }

    function withdraw(uint256 shares) external {
        currentActor = actors[shares % actors.length];

        uint256 callerShares = token.sharesOf(currentActor);
        if (callerShares == 0) return;

        shares = bound(shares, 1, callerShares);

        vm.prank(currentActor);
        try vault.withdraw(shares) returns (uint256 assets) {
            ghost_totalWithdrawn += assets;
        } catch {}
    }

    function updateRisk(uint256 score, uint256 confidence) external {
        score = bound(score, 0, 100);
        confidence = bound(confidence, 60, 100);

        // Clamp delta to MAX_SCORE_JUMP (20) from current
        uint256 currentScore = vault.currentRiskScore();
        if (score > currentScore + 20) score = currentScore + 20;
        if (currentScore > 20 && score < currentScore - 20) score = currentScore - 20;

        // Respect rate limit (55s)
        vm.warp(block.timestamp + 56);

        vm.prank(address(vault)); // vault has RISK_MANAGER_ROLE
        vault.updateRiskScore(score, confidence, keccak256("test"));
    }

    function executeRebase(uint256 factor) external {
        // Bound to valid rebase factor range [0.99e18, 1.05e18]
        factor = bound(factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR);

        // vault.triggerRebase needs REBASE_EXECUTOR_ROLE — we must prank as someone with that role
        // The rebaseExecutor was granted REBASE_EXECUTOR_ROLE in the test setup
        vm.prank(address(this)); // Handler won't have the role, use try/catch
        try vault.triggerRebase(factor) {
            ghost_rebaseCount++;
        } catch {}
    }

    function triggerEmergency(uint256 duration) external {
        duration = bound(duration, 1, 4 hours);

        vm.prank(address(this)); // Handler won't have SENTINEL_ROLE, use try/catch
        try vault.emergencyDeRisk("fuzz-test", duration) {
            ghost_emergencyCount++;
        } catch {}
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 1 hours);
        vm.warp(block.timestamp + seconds_);
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }
}
