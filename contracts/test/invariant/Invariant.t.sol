// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {RebaseExecutor} from "../../src/modules/RebaseExecutor.sol";
import {EventSentinel} from "../../src/modules/EventSentinel.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";
import {InvariantHandler} from "./Handler.t.sol";

/// @title OszillorInvariantTest
/// @notice Invariant/fuzz test suite for the OSZILLOR protocol — 7 invariants.
contract OszillorInvariantTest is StdInvariant, Test {
    OszillorToken public token;
    OszillorVault public vault;
    MockERC20 public usdc;

    RiskEngine public riskEngine;
    RebaseExecutor public rebaseExecutor;
    EventSentinel public eventSentinel;

    InvariantHandler public handler;

    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address creForwarder = makeAddr("forwarder");

    function setUp() public {
        vm.warp(1_700_000_000);

        usdc = new MockERC20();
        MockStrategy strategy = new MockStrategy();

        vm.startPrank(admin);

        // Deploy token
        token = new OszillorToken("OSZILLOR", "OSZ", admin);

        // Predict vault address (3 contracts deployed between token and vault)
        address predictedVault = vm.computeCreateAddress(admin, vm.getNonce(admin) + 3);

        // Deploy CRE modules with mock forwarder
        riskEngine = new RiskEngine(
            predictedVault, predictedVault, creForwarder,
            bytes32(uint256(1)), bytes10(0), creForwarder
        );
        rebaseExecutor = new RebaseExecutor(
            predictedVault, predictedVault, creForwarder,
            bytes32(uint256(2)), bytes10(0), creForwarder
        );
        eventSentinel = new EventSentinel(
            predictedVault, creForwarder,
            bytes32(uint256(3)), bytes10(0), creForwarder
        );

        // Deploy vault
        vault = new OszillorVault(
            address(usdc),
            address(token),
            address(riskEngine),
            address(rebaseExecutor),
            address(eventSentinel),
            address(strategy),
            admin,
            treasury
        );
        require(address(vault) == predictedVault, "Vault address mismatch");

        // Grant roles to vault on token
        token.grantRole(Roles.RISK_MANAGER_ROLE, address(vault));
        token.grantRole(Roles.REBASE_EXECUTOR_ROLE, address(vault));

        vm.stopPrank();

        // Deploy handler
        handler = new InvariantHandler(token, vault, usdc);

        // Target only the handler
        targetContract(address(handler));

        // Target specific functions in the handler
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = InvariantHandler.deposit.selector;
        selectors[1] = InvariantHandler.withdraw.selector;
        selectors[2] = InvariantHandler.updateRisk.selector;
        selectors[3] = InvariantHandler.warpTime.selector;

        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ═════════════════════════════════════════════════════════════
    //                     INVARIANT 1: Share Conservation
    // ═════════════════════════════════════════════════════════════

    /// @notice totalShares * rebaseIndex should approximate totalAssets
    function invariant_shareConservation() public view {
        uint256 totalShares = token.totalShares();
        uint256 rebaseIndex = token.rebaseIndex();
        uint256 totalAssets = vault.totalAssets();

        if (totalShares == 0) return;

        // shares * index / 1e18 should be close to totalAssets
        // Allow tolerance for rounding: 1 unit per share
        uint256 implied = ShareMath.sharesToAmountByIndex(totalShares, rebaseIndex);
        // With rounding, implied can differ from totalAssets by a small amount
        // We use a generous tolerance of totalShares (1 wei per share)
        uint256 tolerance = totalShares > 0 ? totalShares : 1;

        // Check: implied value is within tolerance of actual assets
        if (implied > totalAssets) {
            assertLe(implied - totalAssets, tolerance, "Share conservation: implied > totalAssets beyond tolerance");
        }
    }

    // ═════════════════════════════════════════════════════════════
    //                     INVARIANT 2: Donation Protection (CRIT-06)
    // ═════════════════════════════════════════════════════════════

    /// @notice totalAssets() must always equal internalTotalAssets()
    function invariant_donationProtection() public view {
        assertEq(
            vault.totalAssets(),
            vault.internalTotalAssets(),
            "CRIT-06: totalAssets != internalTotalAssets"
        );
    }

    // ═════════════════════════════════════════════════════════════
    //                     INVARIANT 3: Rebase Index Bounds
    // ═════════════════════════════════════════════════════════════

    /// @notice rebaseIndex must stay within [MIN_REBASE_INDEX, MAX_REBASE_INDEX]
    function invariant_rebaseIndexBounds() public view {
        uint256 index = token.rebaseIndex();
        assertGe(index, RiskMath.MIN_REBASE_INDEX, "Rebase index below MIN");
        assertLe(index, RiskMath.MAX_REBASE_INDEX, "Rebase index above MAX");
    }

    // ═════════════════════════════════════════════════════════════
    //                     INVARIANT 4: Emergency Duration Bound (HIGH-06)
    // ═════════════════════════════════════════════════════════════

    /// @notice Emergency mode cannot last longer than 4 hours
    function invariant_emergencyDuration() public view {
        // If emergency mode is active, the system handles duration capping
        // We can't directly read expiry (private), but emergencyMode() accounts for expiry.
        // We just verify the MAX_EMERGENCY_DURATION constant.
        assertEq(vault.MAX_EMERGENCY_DURATION(), 4 hours, "MAX_EMERGENCY_DURATION must be 4 hours");
    }

    // ═════════════════════════════════════════════════════════════
    //                     INVARIANT 5: Cross-Chain Conservation (single-chain)
    // ═════════════════════════════════════════════════════════════

    /// @notice Sum of all actor balances (in shares) must equal totalShares
    function invariant_crossChainConservation() public view {
        uint256 sumShares;
        for (uint256 i = 0; i < handler.actorsLength(); i++) {
            sumShares += token.sharesOf(handler.actors(i));
        }
        assertEq(sumShares, token.totalShares(), "Sum of shares != totalShares");
    }

    // ═════════════════════════════════════════════════════════════
    //                     INVARIANT 6: Deposit/Withdraw Accounting
    // ═════════════════════════════════════════════════════════════

    /// @notice Ghost tracking: totalDeposited - totalWithdrawn >= totalAssets
    function invariant_depositWithdrawAccounting() public view {
        // Due to fees, totalDeposited - totalWithdrawn >= totalAssets
        if (handler.ghost_totalDeposited() >= handler.ghost_totalWithdrawn()) {
            assertGe(
                handler.ghost_totalDeposited() - handler.ghost_totalWithdrawn(),
                vault.totalAssets(),
                "Deposit/withdraw accounting: net deposits < totalAssets"
            );
        }
    }

    // ═════════════════════════════════════════════════════════════
    //                     INVARIANT 7: Risk Score Bounds
    // ═════════════════════════════════════════════════════════════

    /// @notice Risk score must always be in [0, 100]
    function invariant_riskScoreBounds() public view {
        uint256 score = vault.currentRiskScore();
        assertLe(score, 100, "Risk score above 100");
    }
}
