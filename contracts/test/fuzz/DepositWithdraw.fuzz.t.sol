// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {OszillorVault} from "../../src/core/OszillorVault.sol";
import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {ShareMath} from "../../src/libraries/ShareMath.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";

/// @title DepositWithdrawFuzzTest
/// @author Hitesh (vyqno)
/// @notice Fuzz tests for OszillorVault deposit/withdraw round-trips (Phase 06).
contract DepositWithdrawFuzzTest is Test {
    OszillorVault vault;
    OszillorToken token;
    MockERC20 usdc;

    address admin = makeAddr("admin");
    address riskEngine = makeAddr("riskEngine");
    address rebaseExecutor = makeAddr("rebaseExecutor");
    address sentinel = makeAddr("sentinel");
    address feeRecipient = makeAddr("feeRecipient");

    function setUp() public {
        vm.warp(1_700_000_000);

        usdc = new MockERC20();

        vm.startPrank(admin);

        MockStrategy strategy = new MockStrategy(address(usdc));
        token = new OszillorToken("OSZILLOR", "OSZ", admin);
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

        // Grant vault roles on token
        token.grantRole(Roles.RISK_MANAGER_ROLE, address(vault));
        token.grantRole(Roles.REBASE_EXECUTOR_ROLE, address(vault));

        vm.stopPrank();
    }

    /// @notice Deposit X, withdraw all shares → recovered ≈ X (±1 wei rounding).
    function testFuzz_depositWithdrawRoundTrip(uint256 amount) public {
        // Bound to valid deposit range: [1e15 (MIN_DEPOSIT), uint96 max]
        amount = bound(amount, 1e15, type(uint96).max);

        address user = makeAddr("fuzzUser");
        usdc.mint(user, amount);

        vm.startPrank(user);
        usdc.approve(address(vault), amount);

        uint256 shares = vault.deposit(amount);
        assertGt(shares, 0, "deposit must return > 0 shares");

        uint256 recovered = vault.withdraw(shares);
        vm.stopPrank();

        // Max 1 wei rounding loss
        assertApproxEqAbs(recovered, amount, 1, "round-trip should recover deposit within 1 wei");
    }

    /// @notice Any deposit ≥ MIN_DEPOSIT always produces > 0 shares.
    function testFuzz_depositAlwaysProducesShares(uint256 amount) public {
        amount = bound(amount, 1e15, type(uint96).max);

        address user = makeAddr("fuzzUser2");
        usdc.mint(user, amount);

        vm.startPrank(user);
        usdc.approve(address(vault), amount);

        uint256 shares = vault.deposit(amount);
        vm.stopPrank();

        assertGt(shares, 0, "deposit >= MIN_DEPOSIT must always produce shares");
    }

    /// @notice Two depositors deposit different amounts; each withdraws their proportional share.
    function testFuzz_multipleDepositorsProportional(uint256 amountA, uint256 amountB) public {
        amountA = bound(amountA, 1e15, 1e24); // up to 1M WETH-scale
        amountB = bound(amountB, 1e15, 1e24);

        address userA = makeAddr("userA");
        address userB = makeAddr("userB");
        usdc.mint(userA, amountA);
        usdc.mint(userB, amountB);

        vm.prank(userA);
        usdc.approve(address(vault), amountA);
        vm.prank(userB);
        usdc.approve(address(vault), amountB);

        vm.prank(userA);
        uint256 sharesA = vault.deposit(amountA);

        vm.prank(userB);
        uint256 sharesB = vault.deposit(amountB);

        // Both should have > 0 shares
        assertGt(sharesA, 0);
        assertGt(sharesB, 0);

        // Withdraw
        vm.prank(userA);
        uint256 recoveredA = vault.withdraw(sharesA);

        vm.prank(userB);
        uint256 recoveredB = vault.withdraw(sharesB);

        // Each recovered amount should be close to their deposit
        assertApproxEqAbs(recoveredA, amountA, 1, "userA round-trip");
        assertApproxEqAbs(recoveredB, amountB, 1, "userB round-trip");
    }
}
