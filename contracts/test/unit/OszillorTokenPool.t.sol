// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";

import {OszillorTokenPool} from "../../src/core/OszillorTokenPool.sol";
import {OszillorToken} from "../../src/core/OszillorToken.sol";
import {IOszillorToken} from "../../src/interfaces/IOszillorToken.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {Pool} from "@chainlink/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {TokenPool} from "@chainlink/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@chainlink/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {MockRMN} from "../mocks/MockRMN.sol";
import {MockRouter} from "../mocks/MockRouter.sol";

/// @title OszillorTokenPoolTest
/// @author Hitesh (vyqno)
/// @notice Unit tests for OszillorTokenPool (Phase 07).
contract OszillorTokenPoolTest is Test {
    OszillorTokenPool pool;
    OszillorToken token;
    MockRMN rmn;
    MockRouter router;

    // ── Actors ──
    address admin = makeAddr("admin");
    address alice = makeAddr("alice");
    address onRamp = makeAddr("onRamp");
    address offRamp = makeAddr("offRamp");

    uint64 constant REMOTE_CHAIN = 137; // Polygon selector

    function setUp() public {
        vm.warp(1_700_000_000);

        rmn = new MockRMN();
        router = new MockRouter();

        vm.startPrank(admin);

        // Deploy token
        token = new OszillorToken("OSZILLOR", "OSZ", admin);

        // Deploy pool (empty allowlist = permissionless)
        address[] memory allowlist = new address[](0);
        pool = new OszillorTokenPool(
            address(token),
            allowlist,
            address(rmn),
            address(router)
        );

        // Grant pool RISK_MANAGER_ROLE on token so it can mint/burn shares
        token.grantRole(Roles.RISK_MANAGER_ROLE, address(pool));
        // Grant admin RISK_MANAGER_ROLE so it can mint test shares
        token.grantRole(Roles.RISK_MANAGER_ROLE, admin);

        // Configure remote chain on pool
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);
        bytes[] memory remotePools = new bytes[](1);
        remotePools[0] = abi.encode(address(0xdead)); // remote pool address
        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: REMOTE_CHAIN,
            remotePoolAddresses: remotePools,
            remoteTokenAddress: abi.encode(address(token)), // remote token
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        pool.applyChainUpdates(new uint64[](0), chains);

        vm.stopPrank();

        // Configure router ramps
        router.setOnRamp(REMOTE_CHAIN, onRamp);
        router.setOffRamp(REMOTE_CHAIN, offRamp, true);

        // Mint some shares to Alice for testing lockOrBurn
        vm.prank(admin);
        token.mintShares(alice, 1000e18);
    }

    // ═════════════════════════════════════════════════════════════
    //                      CONSTRUCTOR
    // ═════════════════════════════════════════════════════════════

    function test_constructor_setsToken() public view {
        assertEq(address(pool.getToken()), address(token));
    }

    function test_constructor_setsOszillorToken() public view {
        assertEq(address(pool.oszillorToken()), address(token));
    }

    function test_constructor_setsDecimals() public view {
        assertEq(pool.getTokenDecimals(), 18);
    }

    function test_constructor_setsRouter() public view {
        assertEq(pool.getRouter(), address(router));
    }

    function test_constructor_setsRmnProxy() public view {
        assertEq(pool.getRmnProxy(), address(rmn));
    }

    function test_constructor_supportsChain() public view {
        assertTrue(pool.isSupportedChain(REMOTE_CHAIN));
    }

    // ═════════════════════════════════════════════════════════════
    //                      lockOrBurn
    // ═════════════════════════════════════════════════════════════

    function test_lockOrBurn_burnsShares() public {
        uint256 amount = 100e18; // 100 tokens
        uint256 sharesBefore = token.sharesOf(address(pool));

        // Transfer tokens to pool first (simulating CCIP infrastructure)
        vm.prank(alice);
        token.transfer(address(pool), amount);

        uint256 poolSharesAfterTransfer = token.sharesOf(address(pool));

        // Call lockOrBurn as onRamp
        Pool.LockOrBurnInV1 memory input = Pool.LockOrBurnInV1({
            receiver: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            originalSender: alice,
            amount: amount,
            localToken: address(token)
        });

        vm.prank(onRamp);
        Pool.LockOrBurnOutV1 memory output = pool.lockOrBurn(input);

        // Shares should have been burned
        uint256 poolSharesAfter = token.sharesOf(address(pool));
        assertLt(poolSharesAfter, poolSharesAfterTransfer);

        // destTokenAddress should be set
        assertGt(output.destTokenAddress.length, 0);

        // destPoolData should contain decimals + rebaseIndex
        assertEq(output.destPoolData.length, 64); // abi.encode(uint256, uint256)
    }

    function test_lockOrBurn_encodesRebaseIndex() public {
        uint256 amount = 50e18;

        vm.prank(alice);
        token.transfer(address(pool), amount);

        Pool.LockOrBurnInV1 memory input = Pool.LockOrBurnInV1({
            receiver: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            originalSender: alice,
            amount: amount,
            localToken: address(token)
        });

        vm.prank(onRamp);
        Pool.LockOrBurnOutV1 memory output = pool.lockOrBurn(input);

        (uint256 decimals, uint256 rebaseIdx) = abi.decode(output.destPoolData, (uint256, uint256));
        assertEq(decimals, 18);
        assertEq(rebaseIdx, token.rebaseIndex());
    }

    function test_lockOrBurn_onlyOnRamp() public {
        Pool.LockOrBurnInV1 memory input = Pool.LockOrBurnInV1({
            receiver: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            originalSender: alice,
            amount: 10e18,
            localToken: address(token)
        });

        vm.prank(alice); // not an onRamp
        vm.expectRevert();
        pool.lockOrBurn(input);
    }

    function test_lockOrBurn_emitsEvents() public {
        uint256 amount = 100e18;

        vm.prank(alice);
        token.transfer(address(pool), amount);

        Pool.LockOrBurnInV1 memory input = Pool.LockOrBurnInV1({
            receiver: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            originalSender: alice,
            amount: amount,
            localToken: address(token)
        });

        vm.prank(onRamp);
        vm.expectEmit(true, false, false, false, address(pool));
        emit OszillorTokenPool.SharesBurned(alice, 0, 0); // values not checked
        pool.lockOrBurn(input);
    }

    // ═════════════════════════════════════════════════════════════
    //                    releaseOrMint
    // ═════════════════════════════════════════════════════════════

    function test_releaseOrMint_mintsShares() public {
        uint256 amount = 100e18;
        uint256 sharesBefore = token.sharesOf(alice);

        // Source pool data: abi.encode(18, 1e18) — same decimals, rebaseIndex=1e18
        bytes memory sourcePoolData = abi.encode(uint256(18), uint256(1e18));

        Pool.ReleaseOrMintInV1 memory input = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            receiver: alice,
            amount: amount,
            localToken: address(token),
            sourcePoolAddress: abi.encode(address(0xdead)),
            sourcePoolData: sourcePoolData,
            offchainTokenData: ""
        });

        vm.prank(offRamp);
        Pool.ReleaseOrMintOutV1 memory output = pool.releaseOrMint(input);

        uint256 sharesAfter = token.sharesOf(alice);
        assertGt(sharesAfter, sharesBefore);
        assertGt(output.destinationAmount, 0);
    }

    function test_releaseOrMint_correctShareCalculation() public {
        uint256 amount = 100e18;
        uint256 rebaseIdx = token.rebaseIndex(); // should be 1e18 initially

        bytes memory sourcePoolData = abi.encode(uint256(18), rebaseIdx);

        Pool.ReleaseOrMintInV1 memory input = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            receiver: alice,
            amount: amount,
            localToken: address(token),
            sourcePoolAddress: abi.encode(address(0xdead)),
            sourcePoolData: sourcePoolData,
            offchainTokenData: ""
        });

        uint256 sharesBefore = token.sharesOf(alice);

        vm.prank(offRamp);
        pool.releaseOrMint(input);

        uint256 newShares = token.sharesOf(alice) - sharesBefore;
        // At rebaseIndex = 1e18, shares = amount * 1e18 / 1e18 = amount
        assertEq(newShares, amount);
    }

    function test_releaseOrMint_onlyOffRamp() public {
        Pool.ReleaseOrMintInV1 memory input = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            receiver: alice,
            amount: 10e18,
            localToken: address(token),
            sourcePoolAddress: abi.encode(address(0xdead)),
            sourcePoolData: abi.encode(uint256(18), uint256(1e18)),
            offchainTokenData: ""
        });

        vm.prank(alice); // not an offRamp
        vm.expectRevert();
        pool.releaseOrMint(input);
    }

    function test_releaseOrMint_emitsEvents() public {
        bytes memory sourcePoolData = abi.encode(uint256(18), uint256(1e18));

        Pool.ReleaseOrMintInV1 memory input = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            receiver: alice,
            amount: 100e18,
            localToken: address(token),
            sourcePoolAddress: abi.encode(address(0xdead)),
            sourcePoolData: sourcePoolData,
            offchainTokenData: ""
        });

        vm.prank(offRamp);
        vm.expectEmit(true, false, false, false, address(pool));
        emit OszillorTokenPool.SharesMinted(alice, 0, 0);
        pool.releaseOrMint(input);
    }

    // ═════════════════════════════════════════════════════════════
    //                   SHARE BRIDGING (HIGH-03)
    // ═════════════════════════════════════════════════════════════

    function test_shareBridging_roundTrip() public {
        // Alice has 1000e18 shares initially
        uint256 initialShares = token.sharesOf(alice);
        uint256 bridgeAmount = 500e18; // bridge 500 tokens

        // 1. Transfer tokens to pool (simulating CCIP Lock)
        vm.prank(alice);
        token.transfer(address(pool), bridgeAmount);

        // 2. lockOrBurn on source chain
        Pool.LockOrBurnInV1 memory lockInput = Pool.LockOrBurnInV1({
            receiver: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            originalSender: alice,
            amount: bridgeAmount,
            localToken: address(token)
        });

        vm.prank(onRamp);
        Pool.LockOrBurnOutV1 memory lockOutput = pool.lockOrBurn(lockInput);

        uint256 sharesAfterBurn = token.sharesOf(alice);
        uint256 sharesBurned = initialShares - sharesAfterBurn - token.sharesOf(address(pool));

        // 3. releaseOrMint on destination (simulating same-chain for test)
        Pool.ReleaseOrMintInV1 memory mintInput = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            receiver: alice,
            amount: bridgeAmount,
            localToken: address(token),
            sourcePoolAddress: abi.encode(address(0xdead)),
            sourcePoolData: lockOutput.destPoolData,
            offchainTokenData: ""
        });

        vm.prank(offRamp);
        pool.releaseOrMint(mintInput);

        // 4. Alice should have her shares back (minus any rounding)
        uint256 finalShares = token.sharesOf(alice);
        assertApproxEqAbs(finalShares, initialShares, 1);
    }

    // ═════════════════════════════════════════════════════════════
    //                     EDGE CASES
    // ═════════════════════════════════════════════════════════════

    function test_lockOrBurn_revertsOnCursedRMN() public {
        rmn.setCursed(true);

        vm.prank(alice);
        token.transfer(address(pool), 100e18);

        Pool.LockOrBurnInV1 memory input = Pool.LockOrBurnInV1({
            receiver: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            originalSender: alice,
            amount: 100e18,
            localToken: address(token)
        });

        vm.prank(onRamp);
        vm.expectRevert(TokenPool.CursedByRMN.selector);
        pool.lockOrBurn(input);
    }

    function test_releaseOrMint_revertsOnCursedRMN() public {
        rmn.setCursed(true);

        Pool.ReleaseOrMintInV1 memory input = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            receiver: alice,
            amount: 100e18,
            localToken: address(token),
            sourcePoolAddress: abi.encode(address(0xdead)),
            sourcePoolData: abi.encode(uint256(18), uint256(1e18)),
            offchainTokenData: ""
        });

        vm.prank(offRamp);
        vm.expectRevert(TokenPool.CursedByRMN.selector);
        pool.releaseOrMint(input);
    }

    function test_releaseOrMint_emptySourcePoolData_fallsBackToLocalDecimals() public {
        // When sourcePoolData is empty, should use local decimals (18)
        Pool.ReleaseOrMintInV1 memory input = Pool.ReleaseOrMintInV1({
            originalSender: abi.encode(alice),
            remoteChainSelector: REMOTE_CHAIN,
            receiver: alice,
            amount: 100e18,
            localToken: address(token),
            sourcePoolAddress: abi.encode(address(0xdead)),
            sourcePoolData: "",
            offchainTokenData: ""
        });

        uint256 sharesBefore = token.sharesOf(alice);

        vm.prank(offRamp);
        pool.releaseOrMint(input);

        uint256 newShares = token.sharesOf(alice) - sharesBefore;
        assertEq(newShares, 100e18); // 100 tokens → 100 shares at index 1e18
    }
}
