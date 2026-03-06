// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {VaultStrategy} from "../../src/core/VaultStrategy.sol";
import {IVaultStrategy} from "../../src/interfaces/IVaultStrategy.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {OszillorErrors} from "../../src/libraries/OszillorErrors.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockChainlinkFeed} from "../mocks/MockChainlinkFeed.sol";
import {MockUniswapRouter} from "../mocks/MockUniswapRouter.sol";
import {MockLido} from "../mocks/MockLido.sol";

/// @title VaultStrategyTest
/// @author Hitesh (vyqno)
/// @notice Unit + fuzz tests for VaultStrategy (Phase V2-02).
contract VaultStrategyTest is Test {
    VaultStrategy strategy;
    MockERC20 weth;
    MockERC20 usdc;
    MockLido lido;
    MockUniswapRouter uniRouter;
    MockChainlinkFeed ethUsdFeed;

    address admin = makeAddr("admin");
    address vault = makeAddr("vault"); // STRATEGY_MANAGER_ROLE holder
    address attacker = makeAddr("attacker");

    // ETH/USD = $3000 (8 decimals)
    int256 constant ETH_PRICE = 3000e8;

    function setUp() public {
        weth = new MockERC20();
        usdc = new MockERC20();
        lido = new MockLido(address(weth));
        uniRouter = new MockUniswapRouter(3000e6); // $3000 per ETH
        ethUsdFeed = new MockChainlinkFeed(ETH_PRICE);

        // Configure mock router with token addresses
        uniRouter.setTokens(address(weth), address(usdc));

        // Fund the Uniswap router with tokens for swaps
        weth.mint(address(uniRouter), 1_000_000e18);
        usdc.mint(address(uniRouter), 3_000_000_000e6); // $3B USDC

        vm.startPrank(admin);
        strategy = new VaultStrategy(
            address(weth),
            address(usdc),
            address(lido),
            address(uniRouter),
            address(ethUsdFeed),
            admin
        );

        // Grant STRATEGY_MANAGER_ROLE to vault
        strategy.grantRole(Roles.STRATEGY_MANAGER_ROLE, vault);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════
    //                     CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════

    function test_constructor_setsImmutables() public view {
        assertEq(address(strategy.weth()), address(weth));
        assertEq(address(strategy.usdc()), address(usdc));
        assertEq(address(strategy.lido()), address(lido));
        assertEq(address(strategy.uniRouter()), address(uniRouter));
        assertEq(address(strategy.ethUsdFeed()), address(ethUsdFeed));
    }

    function test_constructor_zeroAddress_reverts() public {
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        new VaultStrategy(address(0), address(usdc), address(lido), address(uniRouter), address(ethUsdFeed), admin);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════

    function test_rebalance_onlyStrategyManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.rebalance(5000);
    }

    function test_hedgeToStable_onlyStrategyManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.hedgeToStable(1e18);
    }

    function test_unhedge_onlyStrategyManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.unhedge(1000e6);
    }

    function test_stakeEth_onlyStrategyManager() public {
        vm.prank(attacker);
        vm.expectRevert();
        strategy.stakeEth(1e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     HEDGE TO STABLE (WETH → USDC)
    // ═══════════════════════════════════════════════════════════════

    function test_hedgeToStable_success() public {
        // Give strategy 10 WETH
        weth.mint(address(strategy), 10e18);

        vm.prank(vault);
        strategy.hedgeToStable(5e18);

        // Strategy should have 5 WETH remaining
        assertEq(weth.balanceOf(address(strategy)), 5e18);
        // Strategy should have ~$15,000 USDC (5 * $3000)
        assertEq(usdc.balanceOf(address(strategy)), 15_000e6);
    }

    function test_hedgeToStable_zeroAmount_reverts() public {
        vm.prank(vault);
        vm.expectRevert(OszillorErrors.ZeroAmount.selector);
        strategy.hedgeToStable(0);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     UNHEDGE (USDC → WETH)
    // ═══════════════════════════════════════════════════════════════

    function test_unhedge_success() public {
        // Give strategy $30,000 USDC
        usdc.mint(address(strategy), 30_000e6);

        vm.prank(vault);
        strategy.unhedge(15_000e6);

        // Strategy should have $15,000 USDC remaining
        assertEq(usdc.balanceOf(address(strategy)), 15_000e6);
        // Strategy should have ~5 WETH ($15000 / $3000)
        assertEq(weth.balanceOf(address(strategy)), 5e18);
    }

    function test_unhedge_zeroAmount_reverts() public {
        vm.prank(vault);
        vm.expectRevert(OszillorErrors.ZeroAmount.selector);
        strategy.unhedge(0);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     REBALANCE
    // ═══════════════════════════════════════════════════════════════

    function test_rebalance_fullEthToFullHedge() public {
        // Start with 10 WETH (100% ETH)
        weth.mint(address(strategy), 10e18);
        assertEq(strategy.currentEthPct(), 10_000); // 100%

        // Rebalance to 0% ETH (full hedge)
        vm.prank(vault);
        strategy.rebalance(0);

        // Should have swapped all WETH to USDC
        assertEq(weth.balanceOf(address(strategy)), 0);
        assertGt(usdc.balanceOf(address(strategy)), 0);
    }

    function test_rebalance_halfHedge() public {
        // Start with 10 WETH
        weth.mint(address(strategy), 10e18);

        // Rebalance to 50% ETH
        vm.prank(vault);
        strategy.rebalance(5000);

        // Should have ~5 WETH and ~$15,000 USDC
        assertApproxEqAbs(weth.balanceOf(address(strategy)), 5e18, 0.1e18);
        assertGt(usdc.balanceOf(address(strategy)), 0);
    }

    function test_rebalance_fullHedgeToFullEth() public {
        // Start with $30,000 USDC (0% ETH)
        usdc.mint(address(strategy), 30_000e6);

        // Rebalance to 100% ETH
        vm.prank(vault);
        strategy.rebalance(10_000);

        // Should have swapped all USDC to WETH
        assertEq(usdc.balanceOf(address(strategy)), 0);
        assertGt(weth.balanceOf(address(strategy)), 0);
    }

    function test_rebalance_noopWhenAtTarget() public {
        // Start with 10 WETH (100% ETH)
        weth.mint(address(strategy), 10e18);

        uint256 wethBefore = weth.balanceOf(address(strategy));

        // Rebalance to 100% ETH — should do nothing
        vm.prank(vault);
        strategy.rebalance(10_000);

        assertEq(weth.balanceOf(address(strategy)), wethBefore);
    }

    function test_rebalance_emptyVault_noop() public {
        // No assets — should not revert
        vm.prank(vault);
        strategy.rebalance(5000);
    }

    function test_rebalance_invalidTarget_reverts() public {
        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(OszillorErrors.InvalidTargetAllocation.selector, 10_001));
        strategy.rebalance(10_001);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function test_totalValueInEth_wethOnly() public {
        weth.mint(address(strategy), 10e18);
        assertEq(strategy.totalValueInEth(), 10e18);
    }

    function test_totalValueInEth_usdcOnly() public {
        usdc.mint(address(strategy), 30_000e6); // $30,000
        // At $3000/ETH, this should be ~10 ETH
        assertApproxEqAbs(strategy.totalValueInEth(), 10e18, 0.01e18);
    }

    function test_totalValueInEth_mixed() public {
        weth.mint(address(strategy), 5e18);    // 5 ETH
        usdc.mint(address(strategy), 15_000e6); // $15,000 = 5 ETH
        // Total ~10 ETH
        assertApproxEqAbs(strategy.totalValueInEth(), 10e18, 0.01e18);
    }

    function test_currentEthPct_allEth() public {
        weth.mint(address(strategy), 10e18);
        assertEq(strategy.currentEthPct(), 10_000);
    }

    function test_currentEthPct_allUsdc() public {
        usdc.mint(address(strategy), 30_000e6);
        assertEq(strategy.currentEthPct(), 0);
    }

    function test_currentEthPct_halfHalf() public {
        weth.mint(address(strategy), 5e18);
        usdc.mint(address(strategy), 15_000e6); // 5 ETH worth
        assertApproxEqAbs(strategy.currentEthPct(), 5000, 10); // ~50%
    }

    function test_currentEthPct_emptyReturnsMax() public view {
        assertEq(strategy.currentEthPct(), 10_000); // default 100%
    }

    // ═══════════════════════════════════════════════════════════════
    //                     PRICE FEED
    // ═══════════════════════════════════════════════════════════════

    function test_stalePriceFeed_reverts() public {
        vm.warp(1_700_000_000); // ensure timestamp is large enough
        weth.mint(address(strategy), 10e18);

        // Set feed updatedAt to 2 hours ago
        ethUsdFeed.setUpdatedAt(block.timestamp - 2 hours);

        vm.prank(vault);
        vm.expectRevert();
        strategy.hedgeToStable(1e18);
    }

    function test_negativePriceFeed_reverts() public {
        weth.mint(address(strategy), 10e18);

        ethUsdFeed.setPrice(-1);

        vm.prank(vault);
        vm.expectRevert();
        strategy.hedgeToStable(1e18);
    }

    // ═══════════════════════════════════════════════════════════════
    //                     FUZZ: REBALANCE
    // ═══════════════════════════════════════════════════════════════

    function testFuzz_rebalance_anyValidTarget(uint256 targetBps) public {
        targetBps = bound(targetBps, 0, 10_000);

        // Start with 10 WETH
        weth.mint(address(strategy), 10e18);

        vm.prank(vault);
        strategy.rebalance(targetBps);

        // Total value should be approximately preserved
        uint256 totalVal = strategy.totalValueInEth();
        assertApproxEqRel(totalVal, 10e18, 0.02e18); // within 2% (slippage)
    }

    function testFuzz_rebalance_invalidTarget_reverts(uint256 targetBps) public {
        targetBps = bound(targetBps, 10_001, type(uint256).max);

        vm.prank(vault);
        vm.expectRevert(abi.encodeWithSelector(OszillorErrors.InvalidTargetAllocation.selector, targetBps));
        strategy.rebalance(targetBps);
    }
}
