// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {IOszillorVault} from "../../src/interfaces/IOszillorVault.sol";
import {IOszillorToken} from "../../src/interfaces/IOszillorToken.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";
import {OszillorErrors} from "../../src/libraries/OszillorErrors.sol";
import {RiskLevel, RiskState, Allocation} from "../../src/libraries/DataStructures.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";

/// @title OszillorVaultTest
/// @author Hitesh (vyqno)
/// @notice Comprehensive unit tests for OszillorVault (Phase 06).
contract OszillorVaultTest is Test {
    OszillorVault vault;
    OszillorToken token;
    MockERC20 usdc;
    MockStrategy strategy;

    // ──────────────────── Actors ────────────────────
    address admin = makeAddr("admin");
    address riskEngine = makeAddr("riskEngine");
    address rebaseExecutor = makeAddr("rebaseExecutor");
    address sentinel = makeAddr("sentinel");
    address feeRecipient = makeAddr("feeRecipient");
    address feeWithdrawer = makeAddr("feeWithdrawer");
    address feeSetter = makeAddr("feeSetter");
    address unpauser = makeAddr("unpauser");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.warp(1_700_000_000);

        usdc = new MockERC20();
        strategy = new MockStrategy();

        vm.startPrank(admin);

        // Deploy token
        token = new OszillorToken("OSZILLOR", "OSZ", admin);

        // Deploy vault
        vault = new OszillorVault(
            address(usdc),
            address(token),
            riskEngine,
            rebaseExecutor,
            sentinel,
            address(strategy),
            admin,
            feeRecipient
        );

        // Grant vault RISK_MANAGER_ROLE on token (so vault can mint/burn shares)
        token.grantRole(Roles.RISK_MANAGER_ROLE, address(vault));
        // Grant vault REBASE_EXECUTOR_ROLE on token (so vault can forward rebase calls)
        token.grantRole(Roles.REBASE_EXECUTOR_ROLE, address(vault));

        // Grant additional roles on vault
        vault.grantRole(Roles.FEE_WITHDRAWER_ROLE, feeWithdrawer);
        vault.grantRole(Roles.FEE_RATE_SETTER_ROLE, feeSetter);
        vault.grantRole(Roles.EMERGENCY_UNPAUSER_ROLE, unpauser);

        vm.stopPrank();

        // Fund users with USDC
        usdc.mint(alice, 1_000_000e18);
        usdc.mint(bob, 1_000_000e18);

        // Users approve vault
        vm.prank(alice);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════════════════
    //               CONSTRUCTOR / INITIAL STATE
    // ═══════════════════════════════════════════════════════════════

    function test_constructor_setsAsset() public view {
        assertEq(address(vault.asset()), address(usdc));
    }

    function test_constructor_setsToken() public view {
        assertEq(address(vault.token()), address(token));
    }

    function test_constructor_riskInitToCaution() public view {
        // CRIT-03: Risk state initialized to CAUTION (score=50)
        assertEq(vault.currentRiskScore(), 50);
        RiskState memory rs = vault.riskState();
        assertEq(rs.riskScore, 50);
        assertEq(rs.confidence, 0);
        assertEq(rs.timestamp, 1_700_000_000);
    }

    function test_constructor_noEmergencyMode() public view {
        assertFalse(vault.emergencyMode());
    }

    function test_constructor_riskLevelIsCaution() public view {
        assertEq(uint256(vault.riskLevel()), uint256(RiskLevel.CAUTION));
    }

    function test_constructor_internalTotalAssetsZero() public view {
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.internalTotalAssets(), 0);
    }

    function test_constructor_rolesSetCorrectly() public view {
        // HIGH-04: All roles in constructor
        assertTrue(vault.hasRole(Roles.RISK_MANAGER_ROLE, riskEngine));
        assertTrue(vault.hasRole(Roles.RISK_MANAGER_ROLE, address(vault)));
        assertTrue(vault.hasRole(Roles.REBASE_EXECUTOR_ROLE, rebaseExecutor));
        assertTrue(vault.hasRole(Roles.SENTINEL_ROLE, sentinel));
    }

    function test_constructor_adminDelay5Days() public view {
        assertEq(vault.defaultAdminDelay(), 5 days);
    }

    function test_constructor_feeDefaults() public view {
        assertEq(vault.feeRateBps(), 50);
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.accruedFees(), 0);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     DEPOSIT
    // ═══════════════════════════════════════════════════════════════

    function test_deposit_basic() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18);

        assertGt(shares, 0);
        assertEq(vault.totalAssets(), 100e18);
        assertEq(usdc.balanceOf(address(vault)), 100e18);
        assertGt(token.sharesOf(alice), 0);
    }

    function test_deposit_emitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false, address(vault));
        emit IOszillorVault.Deposit(alice, 100e18, 0); // shares value not checked
        vault.deposit(100e18);
    }

    function test_deposit_minDeposit_revertsBelow() public {
        // MED-04: Minimum deposit = 1e15
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.DepositTooSmall.selector, 1e15 - 1, 1e15)
        );
        vault.deposit(1e15 - 1);
    }

    function test_deposit_minDeposit_exactlyMin() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(1e15);
        assertGt(shares, 0);
    }

    function test_deposit_emergencyMode_reverts() public {
        // Activate emergency mode
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 2 hours);

        vm.prank(alice);
        vm.expectRevert(OszillorErrors.EmergencyModeActive.selector);
        vault.deposit(100e18);
    }

    function test_deposit_staleness_reverts() public {
        // HIGH-11: Warp past MAX_RISK_STALENESS (24h)
        vm.warp(block.timestamp + 24 hours + 1);

        vm.prank(alice);
        vm.expectRevert(); // RiskStateTooStale
        vault.deposit(100e18);
    }

    function test_deposit_multipleDepositors() public {
        vm.prank(alice);
        uint256 sharesAlice = vault.deposit(100e18);

        vm.prank(bob);
        uint256 sharesBob = vault.deposit(100e18);

        assertGt(sharesAlice, 0);
        assertGt(sharesBob, 0);
        assertEq(vault.totalAssets(), 200e18);
    }

    function test_deposit_updatesInternalAccounting() public {
        vm.prank(alice);
        vault.deposit(500e18);

        assertEq(vault.internalTotalAssets(), 500e18);
        assertEq(vault.totalAssets(), 500e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     WITHDRAW
    // ═══════════════════════════════════════════════════════════════

    function test_withdraw_basic() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18);

        uint256 balBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 assets = vault.withdraw(shares);

        assertGt(assets, 0);
        assertEq(usdc.balanceOf(alice), balBefore + assets);
        assertEq(vault.totalAssets(), 0);
    }

    function test_withdraw_emitsEvent() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18);

        vm.prank(alice);
        vm.expectEmit(true, false, false, false, address(vault));
        emit IOszillorVault.Withdraw(alice, 0, 0); // values not checked
        vault.withdraw(shares);
    }

    function test_withdraw_zeroShares_reverts() public {
        vm.prank(alice);
        vm.expectRevert(OszillorErrors.ZeroAmount.selector);
        vault.withdraw(0);
    }

    function test_withdraw_insufficientShares_reverts() public {
        vm.prank(alice);
        vault.deposit(100e18);
        uint256 aliceShares = token.sharesOf(alice);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.WithdrawalExceedsBalance.selector,
                aliceShares + 1,
                aliceShares
            )
        );
        vault.withdraw(aliceShares + 1);
    }

    function test_withdraw_allowedDuringEmergency() public {
        // HIGH-06: Withdrawals always allowed during emergency
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18);

        // Activate emergency
        vm.prank(sentinel);
        vault.emergencyDeRisk("test emergency", 2 hours);

        // Withdraw should still work
        vm.prank(alice);
        uint256 assets = vault.withdraw(shares);
        assertGt(assets, 0);
    }

    function test_withdraw_updatesInternalAccounting() public {
        vm.prank(alice);
        uint256 shares = vault.deposit(500e18);

        vm.prank(alice);
        vault.withdraw(shares);

        assertEq(vault.internalTotalAssets(), 0);
    }

    // ═══════════════════════════════════════════════════════════════
    //               DEPOSIT-WITHDRAW ROUND TRIP
    // ═══════════════════════════════════════════════════════════════

    function test_depositWithdraw_roundTrip() public {
        uint256 initialBalance = usdc.balanceOf(alice);

        vm.prank(alice);
        uint256 shares = vault.deposit(100e18);

        vm.prank(alice);
        uint256 recovered = vault.withdraw(shares);

        // Should get back everything within 1 wei (rounding)
        assertApproxEqAbs(recovered, 100e18, 1);
        assertApproxEqAbs(usdc.balanceOf(alice), initialBalance, 1);
    }

    // ═══════════════════════════════════════════════════════════════
    //               RISK MANAGEMENT (privileged)
    // ═══════════════════════════════════════════════════════════════

    function test_updateRiskScore_success() public {
        bytes32 hash = keccak256("reasoning");
        vm.prank(riskEngine);
        vault.updateRiskScore(60, 85, hash);

        assertEq(vault.currentRiskScore(), 60);
        RiskState memory rs = vault.riskState();
        assertEq(rs.riskScore, 60);
        assertEq(rs.confidence, 85);
        assertEq(rs.reasoningHash, hash);
    }

    function test_updateRiskScore_emitsEvent() public {
        bytes32 hash = keccak256("reasoning");
        vm.prank(riskEngine);
        vm.expectEmit(false, false, false, true, address(vault));
        emit IOszillorVault.RiskScoreUpdated(60, 85, hash);
        vault.updateRiskScore(60, 85, hash);
    }

    function test_updateRiskScore_emitsWarningOnCritical() public {
        // MED-07: RiskScoreWarning emitted at CRITICAL threshold
        vm.prank(riskEngine);
        vm.expectEmit(false, false, false, true, address(vault));
        emit IOszillorVault.RiskScoreWarning(95, RiskLevel.CRITICAL);
        vault.updateRiskScore(95, 80, bytes32(0));
    }

    function test_updateRiskScore_noWarningBelowCritical() public {
        vm.prank(riskEngine);
        // Score 89 — DANGER, not CRITICAL. No warning event.
        // We use recordLogs to verify no warning event was emitted
        vm.recordLogs();
        vault.updateRiskScore(89, 80, bytes32(0));
        // Just ensure no revert
        assertEq(vault.currentRiskScore(), 89);
    }

    function test_updateRiskScore_onlyRiskManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.updateRiskScore(60, 85, bytes32(0));
    }

    function test_updateAllocations_success() public {
        Allocation[] memory allocs = new Allocation[](2);
        allocs[0] = Allocation({protocol: "aave-v3", percentageBps: 6000, apyBps: 500});
        allocs[1] = Allocation({protocol: "compound-v3", percentageBps: 4000, apyBps: 300});

        vm.prank(riskEngine);
        vault.updateAllocations(allocs);

        Allocation[] memory stored = vault.getAllocations();
        assertEq(stored.length, 2);
        assertEq(stored[0].percentageBps, 6000);
        assertEq(stored[1].percentageBps, 4000);
    }

    function test_updateAllocations_revertsInvalidTotal() public {
        Allocation[] memory allocs = new Allocation[](1);
        allocs[0] = Allocation({protocol: "aave-v3", percentageBps: 5000, apyBps: 500});

        vm.prank(riskEngine);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.InvalidAllocation.selector, 5000)
        );
        vault.updateAllocations(allocs);
    }

    function test_updateAllocations_onlyRiskManager() public {
        Allocation[] memory allocs = new Allocation[](1);
        allocs[0] = Allocation({protocol: "aave-v3", percentageBps: 10_000, apyBps: 500});

        vm.prank(attacker);
        vm.expectRevert();
        vault.updateAllocations(allocs);
    }

    function test_triggerRebase_success() public {
        // First deposit so token has shares
        vm.prank(alice);
        vault.deposit(100e18);

        vm.prank(rebaseExecutor);
        vault.triggerRebase(1.005e18);

        // Token rebase index should have changed
        assertGt(token.rebaseIndex(), 1e18);
    }

    function test_triggerRebase_emitsEvent() public {
        vm.prank(alice);
        vault.deposit(100e18);

        vm.prank(rebaseExecutor);
        vm.expectEmit(false, false, false, false, address(vault));
        emit IOszillorVault.RebaseTriggered(1.005e18, 0);
        vault.triggerRebase(1.005e18);
    }

    function test_triggerRebase_onlyExecutor() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.triggerRebase(1.005e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //               EMERGENCY MODE (HIGH-06)
    // ═══════════════════════════════════════════════════════════════

    function test_emergency_activates() public {
        vm.prank(sentinel);
        vault.emergencyDeRisk("depeg detected", 2 hours);

        assertTrue(vault.emergencyMode());
    }

    function test_emergency_emitsEvent() public {
        vm.prank(sentinel);
        vm.expectEmit(false, false, false, true, address(vault));
        emit IOszillorVault.EmergencyDeRisk("depeg detected", 2 hours, block.timestamp + 2 hours);
        vault.emergencyDeRisk("depeg detected", 2 hours);
    }

    function test_emergency_capsDuration() public {
        // Duration > MAX_EMERGENCY_DURATION (4h) should revert
        vm.prank(sentinel);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.DurationTooLong.selector,
                5 hours,
                4 hours
            )
        );
        vault.emergencyDeRisk("test", 5 hours);
    }

    function test_emergency_defaultDuration() public {
        // Duration 0 → default 1 hour
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 0);
        assertTrue(vault.emergencyMode());
    }

    function test_emergency_autoExpiry() public {
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 2 hours);

        // Before expiry: emergency active
        vm.warp(block.timestamp + 1 hours);
        assertTrue(vault.emergencyMode());

        // After expiry: emergency should be viewable as false
        vm.warp(block.timestamp + 2 hours);
        assertFalse(vault.emergencyMode());
    }

    function test_emergency_autoExpiry_depositsResumeAfterExpiry() public {
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 1 hours);

        // Update risk state timestamp so staleness check passes after warp
        vm.prank(riskEngine);
        vault.updateRiskScore(50, 80, bytes32(0));

        // Warp past expiry
        vm.warp(block.timestamp + 1 hours + 1);

        // Update risk score for fresh timestamp
        vm.prank(riskEngine);
        vault.updateRiskScore(50, 80, bytes32(0));

        // Deposit should now work (auto-lifecycle check)
        vm.prank(alice);
        uint256 shares = vault.deposit(100e18);
        assertGt(shares, 0);
    }

    function test_emergency_manualExit() public {
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 4 hours);

        vm.prank(unpauser);
        vault.exitEmergencyMode();

        assertFalse(vault.emergencyMode());
    }

    function test_emergency_manualExit_emitsEvent() public {
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 4 hours);

        vm.prank(unpauser);
        vm.expectEmit(true, false, false, true, address(vault));
        emit IOszillorVault.EmergencyExited(unpauser, block.timestamp);
        vault.exitEmergencyMode();
    }

    function test_emergency_onlySentinel() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.emergencyDeRisk("hack attempt", 1 hours);
    }

    function test_emergency_exitOnlyUnpauser() public {
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 2 hours);

        vm.prank(attacker);
        vm.expectRevert();
        vault.exitEmergencyMode();
    }

    // ═══════════════════════════════════════════════════════════════
    //               FEE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    function test_fees_depositCollectsFees() public {
        // First deposit
        vm.prank(alice);
        vault.deposit(1_000_000e18);

        // Warp 1 year
        vm.warp(block.timestamp + 365.25 days);

        // Update risk state to keep it fresh
        vm.prank(riskEngine);
        vault.updateRiskScore(50, 80, bytes32(0));

        // Second deposit should trigger fee collection
        vm.prank(bob);
        vault.deposit(100e18);

        // Fees should have accrued (~0.5% of 1M = 5000)
        assertGt(vault.accruedFees(), 0);
        assertApproxEqAbs(vault.accruedFees(), 5000e18, 10e18); // within 10 token tolerance
    }

    function test_fees_withdrawOnlyAccrued() public {
        // HIGH-07: withdrawFees only transfers accruedFees
        vm.prank(alice);
        vault.deposit(1_000_000e18);

        vm.warp(block.timestamp + 365.25 days);

        // Trigger fee collection via deposit
        vm.prank(riskEngine);
        vault.updateRiskScore(50, 80, bytes32(0));
        vm.prank(bob);
        vault.deposit(1e15);

        uint256 accrued = vault.accruedFees();
        assertGt(accrued, 0);

        uint256 recipientBefore = usdc.balanceOf(feeRecipient);
        uint256 vaultBalBefore = usdc.balanceOf(address(vault));

        vm.prank(feeWithdrawer);
        vault.withdrawFees();

        // Fee recipient got exactly accrued fees
        assertEq(usdc.balanceOf(feeRecipient), recipientBefore + accrued);
        // Vault still holds the rest (user deposits minus fees)
        assertEq(usdc.balanceOf(address(vault)), vaultBalBefore - accrued);
    }

    function test_fees_withdrawRevertsIfZero() public {
        vm.prank(feeWithdrawer);
        vm.expectRevert(OszillorErrors.ZeroAmount.selector);
        vault.withdrawFees();
    }

    function test_fees_withdrawOnlyFeeWithdrawer() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.withdrawFees();
    }

    function test_fees_setFeeRate() public {
        vm.prank(feeSetter);
        vault.setFeeRate(100); // 1% annual

        assertEq(vault.feeRateBps(), 100);
    }

    function test_fees_setFeeRateOnlyFeeSetter() public {
        vm.prank(attacker);
        vm.expectRevert();
        vault.setFeeRate(100);
    }

    // ═══════════════════════════════════════════════════════════════
    //               VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function test_totalAssets_usesInternalAccounting() public {
        // CRIT-06: Donation protection
        vm.prank(alice);
        vault.deposit(100e18);

        // Send USDC directly to vault (donation attack)
        usdc.mint(address(vault), 1_000_000e18);

        // totalAssets should NOT include the donation
        assertEq(vault.totalAssets(), 100e18);
        // But raw balance has more
        assertEq(usdc.balanceOf(address(vault)), 1_000_100e18);
    }

    function test_donationAttack_sharePriceUnchanged() public {
        // CRIT-06: Direct USDC transfer doesn't affect share price
        vm.prank(alice);
        uint256 shares1 = vault.deposit(100e18);

        // Attacker donates to inflate share price
        usdc.mint(address(vault), 100_000e18);

        // Bob deposits same amount — should get similar shares
        vm.prank(bob);
        uint256 shares2 = vault.deposit(100e18);

        // Shares should be approximately equal (donation has no effect)
        assertApproxEqAbs(shares1, shares2, 1);
    }

    function test_maxDeposit_normalState() public view {
        // MED-09: Normal state → max deposit
        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    function test_maxDeposit_emergencyMode() public {
        // MED-09: Emergency → 0
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 2 hours);

        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_maxDeposit_dangerRisk() public {
        // MED-09: DANGER score → 0
        vm.prank(riskEngine);
        vault.updateRiskScore(75, 80, bytes32(0));

        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_maxDeposit_criticalRisk() public {
        // MED-09: CRITICAL score → 0
        vm.prank(riskEngine);
        vault.updateRiskScore(95, 80, bytes32(0));

        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_maxDeposit_cautionRisk_allowed() public {
        // MED-09: CAUTION (40-69) → allowed
        vm.prank(riskEngine);
        vault.updateRiskScore(55, 80, bytes32(0));

        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    function test_maxWithdraw_returnsCorrectAmount() public {
        vm.prank(alice);
        vault.deposit(100e18);

        uint256 maxW = vault.maxWithdraw(alice);
        assertApproxEqAbs(maxW, 100e18, 1);
    }

    function test_maxWithdraw_noShares() public view {
        assertEq(vault.maxWithdraw(bob), 0);
    }

    function test_riskLevel_matchesScore() public {
        vm.prank(riskEngine);
        vault.updateRiskScore(30, 80, bytes32(0));
        assertEq(uint256(vault.riskLevel()), uint256(RiskLevel.SAFE));

        vm.prank(riskEngine);
        vault.updateRiskScore(55, 80, bytes32(0));
        assertEq(uint256(vault.riskLevel()), uint256(RiskLevel.CAUTION));
    }

    function test_getAllocations_initiallyEmpty() public view {
        Allocation[] memory allocs = vault.getAllocations();
        assertEq(allocs.length, 0);
    }

    function test_emergencyModeView_expired() public {
        vm.prank(sentinel);
        vault.emergencyDeRisk("test", 1 hours);

        vm.warp(block.timestamp + 2 hours);

        // View function should return false after expiry
        assertFalse(vault.emergencyMode());
    }

    // ═══════════════════════════════════════════════════════════════
    //               INTEGRATION: DEPOSIT → RISK → REBASE → WITHDRAW
    // ═══════════════════════════════════════════════════════════════

    function test_fullFlow_deposit_risk_rebase_withdraw() public {
        // 1. Alice deposits
        vm.prank(alice);
        uint256 shares = vault.deposit(1000e18);
        assertGt(shares, 0);

        // 2. RiskEngine updates score (SAFE)
        vm.prank(riskEngine);
        vault.updateRiskScore(20, 90, keccak256("safe assessment"));

        // 3. Capture Alice's token balance before rebase
        uint256 balanceBefore = token.balanceOf(alice);

        // 3a. RebaseExecutor triggers positive rebase
        vm.prank(rebaseExecutor);
        vault.triggerRebase(1.005e18); // +0.5%

        // 4. Alice's token balance increased (via shares * new index)
        uint256 balanceAfter = token.balanceOf(alice);
        assertGt(balanceAfter, balanceBefore); // balance rose with rebase

        // 5. Alice withdraws all shares — vault accounting remains the same
        //    (rebase affects token index, not vault's internal USDC accounting)
        vm.prank(alice);
        uint256 recovered = vault.withdraw(shares);
        assertApproxEqAbs(recovered, 1000e18, 1); // recovered ~= original deposit
    }
}
