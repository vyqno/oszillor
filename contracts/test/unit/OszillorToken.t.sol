// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {IOszillorToken} from "../../src/interfaces/IOszillorToken.sol";
import {IERC677Receiver} from "../../src/interfaces/IERC677Receiver.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";
import {OszillorErrors} from "../../src/libraries/OszillorErrors.sol";

/// @title OszillorTokenTest
/// @author Hitesh (vyqno)
/// @notice Comprehensive unit tests for OszillorToken (Phase 05).
contract OszillorTokenTest is Test {
    OszillorToken token;

    address admin = makeAddr("admin");
    address vault = makeAddr("vault");        // RISK_MANAGER_ROLE
    address executor = makeAddr("executor");  // REBASE_EXECUTOR_ROLE
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.warp(1_700_000_000);

        vm.startPrank(admin);
        token = new OszillorToken("OSZILLOR", "OSZ", admin);
        token.grantRole(Roles.RISK_MANAGER_ROLE, vault);
        token.grantRole(Roles.REBASE_EXECUTOR_ROLE, executor);
        vm.stopPrank();

        // Mint some shares to alice for testing
        vm.prank(vault);
        token.mintShares(alice, 1000e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     CONSTRUCTOR / INITIAL STATE
    // ═══════════════════════════════════════════════════════════════

    function test_constructor_setsName() public view {
        assertEq(token.name(), "OSZILLOR");
        assertEq(token.symbol(), "OSZ");
    }

    function test_constructor_initialIndex() public view {
        assertEq(token.rebaseIndex(), 1e18);
    }

    function test_constructor_adminDelay5Days() public view {
        assertEq(token.defaultAdminDelay(), 5 days);
    }

    function test_constructor_initialTimestamp() public view {
        assertEq(token.lastRebaseTimestamp(), block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     BALANCE / SUPPLY (share-based)
    // ═══════════════════════════════════════════════════════════════

    function test_balanceOf_atInitialIndex() public view {
        // index=1e18: shares == amounts
        assertEq(token.balanceOf(alice), 1000e18);
    }

    function test_totalSupply_atInitialIndex() public view {
        assertEq(token.totalSupply(), 1000e18);
    }

    function test_sharesOf_returnsRawShares() public view {
        assertEq(token.sharesOf(alice), 1000e18);
    }

    function test_balanceOf_adjustsAfterRebase() public {
        // Positive rebase: +1%
        vm.prank(executor);
        token.rebase(1.01e18);

        // Balance should increase by ~1%
        assertApproxEqAbs(token.balanceOf(alice), 1010e18, 1);
        // Shares unchanged
        assertEq(token.sharesOf(alice), 1000e18);
    }

    function test_totalSupply_adjustsAfterRebase() public {
        vm.prank(executor);
        token.rebase(1.005e18);

        assertApproxEqAbs(token.totalSupply(), 1005e18, 1);
    }

    function test_balanceOf_adjustsAfterNegativeRebase() public {
        vm.prank(executor);
        token.rebase(0.995e18);

        // -0.5% rebase
        assertApproxEqAbs(token.balanceOf(alice), 995e18, 1);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     MINT / BURN SHARES
    // ═══════════════════════════════════════════════════════════════

    function test_mintShares_onlyRiskManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.mintShares(bob, 100e18);
    }

    function test_mintShares_success() public {
        vm.prank(vault);
        token.mintShares(bob, 500e18);

        assertEq(token.sharesOf(bob), 500e18);
        assertEq(token.totalShares(), 1500e18);
    }

    function test_mintShares_emitsTransferSharesEvent() public {
        vm.prank(vault);
        vm.expectEmit(true, true, false, true, address(token));
        emit IOszillorToken.TransferShares(address(0), bob, 500e18);
        token.mintShares(bob, 500e18);
    }

    function test_mintShares_revertsZeroAddress() public {
        vm.prank(vault);
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        token.mintShares(address(0), 100e18);
    }

    function test_mintShares_revertsZeroAmount() public {
        vm.prank(vault);
        vm.expectRevert(OszillorErrors.ZeroAmount.selector);
        token.mintShares(bob, 0);
    }

    function test_burnShares_success() public {
        vm.prank(vault);
        token.burnShares(alice, 500e18);

        assertEq(token.sharesOf(alice), 500e18);
        assertEq(token.totalShares(), 500e18);
    }

    function test_burnShares_onlyRiskManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.burnShares(alice, 100e18);
    }

    function test_burnShares_revertsInsufficientShares() public {
        vm.prank(vault);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.InsufficientShares.selector, 2000e18, 1000e18)
        );
        token.burnShares(alice, 2000e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     TRANSFER (share-based)
    // ═══════════════════════════════════════════════════════════════

    function test_transfer_movesShares() public {
        vm.prank(alice);
        token.transfer(bob, 500e18);

        assertEq(token.sharesOf(alice), 500e18);
        assertEq(token.sharesOf(bob), 500e18);
    }

    function test_transfer_revertsInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert(); // InsufficientShares
        token.transfer(bob, 2000e18);
    }

    function test_transfer_revertsToZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        token.transfer(address(0), 100e18);
    }

    function test_transfer_afterRebase_movesCorrectShares() public {
        // Rebase +1%
        vm.prank(executor);
        token.rebase(1.01e18);

        // Alice balance is ~1010e18. Transfer 505e18 (half of rebased balance)
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 halfBalance = aliceBalance / 2;

        vm.prank(alice);
        token.transfer(bob, halfBalance);

        // Both should have ~half the shares
        assertApproxEqAbs(token.sharesOf(alice), token.sharesOf(bob), 1);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     ALLOWANCE (share-based, HIGH-01)
    // ═══════════════════════════════════════════════════════════════

    function test_approve_storesInShares() public {
        vm.prank(alice);
        token.approve(bob, 100e18);

        // At index 1e18, share allowance should equal amount
        assertEq(token.shareAllowance(alice, bob), 100e18);
        assertEq(token.allowance(alice, bob), 100e18);
    }

    function test_allowance_adjustsWithRebase() public {
        // Approve 100 OSZ at index 1e18
        vm.prank(alice);
        token.approve(bob, 100e18);

        // Rebase +1% → index = 1.01e18
        vm.prank(executor);
        token.rebase(1.01e18);

        // Share allowance unchanged (100e18 shares), but amount-denominated
        // allowance should be ~101e18 (100 shares * 1.01 index)
        assertEq(token.shareAllowance(alice, bob), 100e18);
        assertApproxEqAbs(token.allowance(alice, bob), 101e18, 1);
    }

    function test_transferFrom_spendsShareAllowance() public {
        vm.prank(alice);
        token.approve(bob, 200e18);

        vm.prank(bob);
        token.transferFrom(alice, bob, 100e18);

        // Half the share allowance consumed
        assertApproxEqAbs(token.shareAllowance(alice, bob), 100e18, 1);
        assertEq(token.sharesOf(bob), 100e18);
    }

    function test_transferFrom_revertsInsufficientAllowance() public {
        vm.prank(alice);
        token.approve(bob, 50e18);

        vm.prank(bob);
        vm.expectRevert(); // InsufficientShareAllowance
        token.transferFrom(alice, bob, 100e18);
    }

    function test_transferFrom_maxApproval_doesNotDecrease() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, bob, 100e18);

        // Max approval should not decrease
        assertEq(token.shareAllowance(alice, bob), type(uint256).max);
    }

    function test_approveShares_directShareApproval() public {
        vm.prank(alice);
        token.approveShares(bob, 500e18);

        assertEq(token.shareAllowance(alice, bob), 500e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     REBASE
    // ═══════════════════════════════════════════════════════════════

    function test_rebase_onlyExecutor() public {
        vm.prank(attacker);
        vm.expectRevert();
        token.rebase(1.005e18);
    }

    function test_rebase_updatesIndex() public {
        vm.prank(executor);
        uint256 newIndex = token.rebase(1.005e18);

        assertEq(token.rebaseIndex(), newIndex);
        assertApproxEqAbs(newIndex, 1.005e18, 1);
    }

    function test_rebase_emitsEvent() public {
        vm.prank(executor);
        vm.expectEmit(true, false, false, true, address(token));
        emit IOszillorToken.Rebase(1, 1.005e18);
        token.rebase(1.005e18);
    }

    function test_rebase_incrementsEpoch() public {
        vm.prank(executor);
        token.rebase(1.005e18);
        assertEq(token.epoch(), 1);

        vm.prank(executor);
        token.rebase(1.003e18);
        assertEq(token.epoch(), 2);
    }

    function test_rebase_rejectsFactorBelowMin() public {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.RebaseFactorOutOfBounds.selector,
                0.98e18, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR
            )
        );
        token.rebase(0.98e18);
    }

    function test_rebase_rejectsFactorAboveMax() public {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.RebaseFactorOutOfBounds.selector,
                1.02e18, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR
            )
        );
        token.rebase(1.02e18);
    }

    function test_rebase_indexClampedToFloor() public {
        // Start at normal index, apply repeated -1% rebases
        // After many, index should floor at MIN_REBASE_INDEX
        for (uint256 i = 0; i < 500; i++) {
            vm.prank(executor);
            token.rebase(RiskMath.MIN_REBASE_FACTOR);
        }
        assertGe(token.rebaseIndex(), RiskMath.MIN_REBASE_INDEX);
    }

    function test_rebase_indexClampedToCeiling() public {
        for (uint256 i = 0; i < 500; i++) {
            vm.prank(executor);
            token.rebase(RiskMath.MAX_REBASE_FACTOR);
        }
        assertLe(token.rebaseIndex(), RiskMath.MAX_REBASE_INDEX);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     ERC-677 transferAndCall (HIGH-02)
    // ═══════════════════════════════════════════════════════════════

    function test_transferAndCall_toEOA() public {
        vm.prank(alice);
        token.transferAndCall(bob, 100e18, "");

        assertEq(token.sharesOf(bob), 100e18);
    }

    function test_transferAndCall_callsCallback() public {
        MockERC677Receiver receiver = new MockERC677Receiver();

        vm.prank(alice);
        token.transferAndCall(address(receiver), 100e18, "hello");

        assertTrue(receiver.called());
        assertEq(receiver.lastSender(), alice);
        assertEq(receiver.lastValue(), 100e18);
        assertEq(receiver.lastData(), "hello");
    }

    function test_transferAndCall_reentrancyReverts() public {
        ReentrantReceiver reentranter = new ReentrantReceiver(address(token));

        vm.prank(vault);
        token.mintShares(address(reentranter), 1000e18);

        vm.prank(address(reentranter));
        vm.expectRevert(); // ReentrancyGuard
        token.transferAndCall(address(reentranter), 100e18, "");
    }

    // ═══════════════════════════════════════════════════════════════
    //                     EDGE CASES
    // ═══════════════════════════════════════════════════════════════

    function test_zeroBalanceUser_hasNoShares() public view {
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.sharesOf(bob), 0);
    }

    function test_multipleRebases_compounding() public {
        // Apply 3 positive rebases of +0.5%
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(executor);
            token.rebase(1.005e18);
        }

        // 1e18 * 1.005^3 ≈ 1.015075e18
        uint256 expectedIndex = 1.015075125e18;
        assertApproxEqAbs(token.rebaseIndex(), expectedIndex, 1e9); // within 1 Gwei precision
    }
}

// ══════════════════════════════════════════════════════════════════
//                     HELPER CONTRACTS
// ══════════════════════════════════════════════════════════════════

contract MockERC677Receiver is IERC677Receiver {
    bool public called;
    address public lastSender;
    uint256 public lastValue;
    bytes public lastData;

    function onTokenTransfer(address sender, uint256 value, bytes calldata data) external override {
        called = true;
        lastSender = sender;
        lastValue = value;
        lastData = data;
    }
}

contract ReentrantReceiver is IERC677Receiver {
    OszillorToken immutable token;

    constructor(address _token) {
        token = OszillorToken(_token);
    }

    function onTokenTransfer(address, uint256, bytes calldata) external override {
        // Attempt reentrant transferAndCall
        token.transferAndCall(address(this), 50e18, "");
    }
}
