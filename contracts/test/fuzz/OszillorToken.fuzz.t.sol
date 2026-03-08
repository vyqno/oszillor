// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";

/// @title OszillorTokenFuzzTest
/// @author Hitesh (vyqno)
/// @notice Fuzz tests for OszillorToken — share round-trips, index bounds, allowance invariants.
contract OszillorTokenFuzzTest is Test {
    OszillorToken token;
    address admin = makeAddr("admin");
    address vault = makeAddr("vault");
    address executor = makeAddr("executor");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.warp(1_700_000_000);

        vm.startPrank(admin);
        token = new OszillorToken("OSZILLOR", "OSZ", admin);
        token.grantRole(Roles.TOKEN_MINTER_ROLE, vault);
        token.grantRole(Roles.REBASE_EXECUTOR_ROLE, executor);
        vm.stopPrank();
    }

    /// @notice Minting then burning the same shares should return to zero.
    function testFuzz_mintBurnRoundTrip(uint256 shares) public {
        shares = bound(shares, 1, type(uint128).max);

        vm.prank(vault);
        token.mintShares(alice, shares);
        assertEq(token.sharesOf(alice), shares);

        vm.prank(vault);
        token.burnShares(alice, shares);
        assertEq(token.sharesOf(alice), 0);
        assertEq(token.totalShares(), 0);
    }

    /// @notice balanceOf should always equal shares * index / 1e18.
    function testFuzz_balanceOf_equalsSharesTimesIndex(uint256 shares, uint256 factor) public {
        shares = bound(shares, 1, type(uint96).max);
        factor = bound(factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR);

        vm.prank(vault);
        token.mintShares(alice, shares);

        vm.prank(executor);
        token.rebase(factor);

        uint256 expected = ShareMath.sharesToAmountByIndex(shares, token.rebaseIndex());
        assertEq(token.balanceOf(alice), expected);
    }

    /// @notice totalSupply should always equal totalShares * index / 1e18.
    function testFuzz_totalSupply_consistent(uint256 shares, uint256 factor) public {
        shares = bound(shares, 1, type(uint96).max);
        factor = bound(factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR);

        vm.prank(vault);
        token.mintShares(alice, shares);

        vm.prank(executor);
        token.rebase(factor);

        uint256 expected = ShareMath.sharesToAmountByIndex(token.totalShares(), token.rebaseIndex());
        assertEq(token.totalSupply(), expected);
    }

    /// @notice After any valid rebase, index stays within [MIN, MAX].
    function testFuzz_rebase_indexAlwaysInBounds(uint256 factor) public {
        factor = bound(factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR);

        vm.prank(executor);
        token.rebase(factor);

        assertGe(token.rebaseIndex(), RiskMath.MIN_REBASE_INDEX);
        assertLe(token.rebaseIndex(), RiskMath.MAX_REBASE_INDEX);
    }

    /// @notice Transfer preserves total shares invariant.
    function testFuzz_transfer_preservesTotalShares(uint256 shares, uint256 transferAmount) public {
        shares = bound(shares, 1e6, type(uint96).max);

        vm.prank(vault);
        token.mintShares(alice, shares);

        uint256 aliceBalance = token.balanceOf(alice);
        transferAmount = bound(transferAmount, 1, aliceBalance);

        uint256 totalBefore = token.totalShares();

        vm.prank(alice);
        token.transfer(bob, transferAmount);

        assertEq(token.totalShares(), totalBefore);
    }

    /// @notice Share allowance adjusts correctly after rebase.
    function testFuzz_allowance_adjustsWithRebase(uint256 approveAmount, uint256 factor) public {
        approveAmount = bound(approveAmount, 1e6, type(uint96).max);
        factor = bound(factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR);

        vm.prank(vault);
        token.mintShares(alice, type(uint96).max);

        vm.prank(alice);
        token.approve(bob, approveAmount);

        uint256 sharesBefore = token.shareAllowance(alice, bob);

        vm.prank(executor);
        token.rebase(factor);

        // Share allowance should NOT change after rebase
        assertEq(token.shareAllowance(alice, bob), sharesBefore);

        // Amount-denominated allowance should change
        uint256 expectedAmount = ShareMath.sharesToAmountByIndex(sharesBefore, token.rebaseIndex());
        assertEq(token.allowance(alice, bob), expectedAmount);
    }

    /// @notice Repeated rebases never push index to zero or overflow.
    function testFuzz_repeatedRebases_indexSafe(uint8 count, uint256 factor) public {
        count = uint8(bound(count, 1, 50));
        factor = bound(factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR);

        for (uint256 i = 0; i < count; i++) {
            vm.prank(executor);
            token.rebase(factor);
        }

        assertGe(token.rebaseIndex(), RiskMath.MIN_REBASE_INDEX);
        assertLe(token.rebaseIndex(), RiskMath.MAX_REBASE_INDEX);
        assertGt(token.rebaseIndex(), 0); // Never zero
    }
}
