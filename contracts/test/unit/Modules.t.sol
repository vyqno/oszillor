// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {Roles} from "../../src/libraries/Roles.sol";
import {OszillorErrors} from "../../src/libraries/OszillorErrors.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";
import {RiskReport, RebaseReport, RebalanceReport, ThreatReport, Allocation, RiskLevel} from "../../src/libraries/DataStructures.sol";

import {ConcretePausableAC} from "../mocks/ConcretePausableAC.sol";
import {ConcreteOszillorFees} from "../mocks/ConcreteOszillorFees.sol";
import {MockVault} from "../mocks/MockVault.sol";
import {MockPausable} from "../mocks/MockPausable.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {RiskEngine} from "../../src/modules/RiskEngine.sol";
import {RebaseExecutor} from "../../src/modules/RebaseExecutor.sol";
import {EventSentinel} from "../../src/modules/EventSentinel.sol";
import {RiskRegistry} from "../../src/modules/RiskRegistry.sol";

/// @title ModulesTest
/// @author Hitesh (vyqno)
/// @notice Unit tests for OSZILLOR Layer 3 modules.
contract ModulesTest is Test {
    // ──────────────────── Actors ────────────────────
    address admin = makeAddr("admin");
    address pauser = makeAddr("pauser");
    address unpauser = makeAddr("unpauser");
    address feeRecipient = makeAddr("feeRecipient");
    address attacker = makeAddr("attacker");
    address forwarder = makeAddr("forwarder");
    address workflowOwner = makeAddr("workflowOwner");

    bytes32 workflowId = keccak256("test-workflow");
    bytes10 workflowName = bytes10(keccak256("wf-name"));

    // ──────────────────── Contracts ────────────────────
    ConcretePausableAC pac;
    MockVault vault;
    MockPausable pausable;
    RiskEngine riskEngine;
    RebaseExecutor rebaseExecutor;
    EventSentinel eventSentinel;
    RiskRegistry registry;
    ConcreteOszillorFees fees;
    MockERC20 usdc;

    function setUp() public {
        // Warp to realistic timestamp so rate-limit checks work
        vm.warp(1_700_000_000);
        vm.startPrank(admin);

        // PausableWithAccessControl
        pac = new ConcretePausableAC(admin);
        pac.grantRole(Roles.EMERGENCY_PAUSER_ROLE, pauser);
        pac.grantRole(Roles.EMERGENCY_UNPAUSER_ROLE, unpauser);

        // Mocks
        vault = new MockVault();
        pausable = new MockPausable();

        // CRE Receivers
        riskEngine = new RiskEngine(
            address(vault), address(pausable),
            forwarder, workflowId, workflowName, workflowOwner
        );
        rebaseExecutor = new RebaseExecutor(
            address(vault), address(pausable),
            forwarder, workflowId, workflowName, workflowOwner
        );
        eventSentinel = new EventSentinel(
            address(vault),
            forwarder, workflowId, workflowName, workflowOwner
        );

        // RiskRegistry
        registry = new RiskRegistry(admin);

        // Fees
        usdc = new MockERC20();
        fees = new ConcreteOszillorFees(address(usdc), feeRecipient);

        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════
    //               PAUSABLE WITH ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════

    function test_pac_pauserCanPause() public {
        vm.prank(pauser);
        pac.emergencyPause();
        assertTrue(pac.paused());
    }

    function test_pac_unpauserCanUnpause() public {
        vm.prank(pauser);
        pac.emergencyPause();
        vm.prank(unpauser);
        pac.emergencyUnpause();
        assertFalse(pac.paused());
    }

    function test_pac_pauserCannotUnpause() public {
        vm.prank(pauser);
        pac.emergencyPause();
        vm.prank(pauser);
        vm.expectRevert();
        pac.emergencyUnpause();
    }

    function test_pac_unpauserCannotPause() public {
        vm.prank(unpauser);
        vm.expectRevert();
        pac.emergencyPause();
    }

    function test_pac_randomCannotPause() public {
        vm.prank(attacker);
        vm.expectRevert();
        pac.emergencyPause();
    }

    function test_pac_adminTransferDelay_is5Days() public view {
        assertEq(pac.defaultAdminDelay(), 5 days);
    }

    function test_pac_supportsAccessControlInterface() public view {
        assertTrue(pac.supportsInterface(type(IAccessControl).interfaceId));
    }

    function test_pac_roleEnumeration() public view {
        assertTrue(pac.hasRole(Roles.EMERGENCY_PAUSER_ROLE, pauser));
        assertTrue(pac.hasRole(Roles.EMERGENCY_UNPAUSER_ROLE, unpauser));
        assertFalse(pac.hasRole(Roles.EMERGENCY_PAUSER_ROLE, attacker));
    }

    // ═══════════════════════════════════════════════════════════════
    //                      CRE RECEIVER
    // ═══════════════════════════════════════════════════════════════

    function test_cre_immutableParams() public view {
        assertEq(riskEngine.FORWARDER(), forwarder);
        assertEq(riskEngine.WORKFLOW_ID(), workflowId);
        assertEq(riskEngine.WORKFLOW_NAME(), workflowName);
        assertEq(riskEngine.WORKFLOW_OWNER(), workflowOwner);
    }

    function test_cre_rejectsWrongForwarder() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.NotForwarder.selector, attacker, forwarder)
        );
        riskEngine.onReport(metadata, report);
    }

    function test_cre_rejectsWrongWorkflowId() public {
        bytes32 wrongId = keccak256("wrong");
        bytes memory metadata = _buildMetadata(wrongId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.WrongWorkflow.selector, wrongId, workflowId)
        );
        riskEngine.onReport(metadata, report);
    }

    function test_cre_rejectsWrongOwner() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, attacker);
        bytes memory report = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.WrongOwner.selector, attacker, workflowOwner)
        );
        riskEngine.onReport(metadata, report);
    }

    function test_cre_rejectsWrongName() public {
        bytes10 wrongName = bytes10(keccak256("wrong-name"));
        bytes memory metadata = _buildMetadata(workflowId, wrongName, workflowOwner);
        bytes memory report = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.WrongName.selector,
                bytes32(wrongName),
                bytes32(workflowName)
            )
        );
        riskEngine.onReport(metadata, report);
    }

    // ═══════════════════════════════════════════════════════════════
    //                      RISK ENGINE
    // ═══════════════════════════════════════════════════════════════

    function test_riskEngine_processesValidReport() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        riskEngine.onReport(metadata, report);

        assertEq(vault.currentRiskScore(), 55);
        assertEq(vault.updateRiskScoreCallCount(), 1);
    }

    function test_riskEngine_rateLimit_revertsTooFrequent() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        riskEngine.onReport(metadata, report);

        // Try again immediately — should revert
        bytes memory report2 = _buildRiskReport(56, 80, bytes32(uint256(2)));
        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.UpdateTooFrequent.selector,
                block.timestamp + 55 seconds
            )
        );
        riskEngine.onReport(metadata, report2);
    }

    function test_riskEngine_rateLimit_allowsAfterInterval() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report1 = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        riskEngine.onReport(metadata, report1);

        // Warp past interval
        vm.warp(block.timestamp + 56 seconds);

        bytes memory report2 = _buildRiskReport(60, 80, bytes32(uint256(2)));
        vm.prank(forwarder);
        riskEngine.onReport(metadata, report2);

        assertEq(vault.currentRiskScore(), 60);
        assertEq(vault.updateRiskScoreCallCount(), 2);
    }

    function test_riskEngine_confidenceGate_revertsLowConfidence() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(55, 59, bytes32(uint256(1))); // confidence < 60

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.ConfidenceTooLow.selector, 59, 60)
        );
        riskEngine.onReport(metadata, report);
    }

    function test_riskEngine_deltaClamp_revertsLargeJump() public {
        // Vault starts at score=50. Try to jump to 75 (delta=25 > 20)
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(75, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.ScoreJumpTooLarge.selector, 25, 20)
        );
        riskEngine.onReport(metadata, report);
    }

    function test_riskEngine_deltaClamp_allowsWithinBounds() public {
        // Vault starts at score=50. Jump to 70 (delta=20 == max)
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(70, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        riskEngine.onReport(metadata, report);
        assertEq(vault.currentRiskScore(), 70);
    }

    function test_riskEngine_pauseCheck_revertsWhenPaused() public {
        pausable.setPaused(true);

        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(55, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        vm.expectRevert(OszillorErrors.SystemPaused.selector);
        riskEngine.onReport(metadata, report);
    }

    function test_riskEngine_emitsWarning_onCriticalThreshold() public {
        // Set vault score to 75 directly (within delta=15 of target 90).
        vault.setRiskScore(75);

        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRiskReport(90, 80, bytes32(uint256(1)));

        vm.prank(forwarder);
        // Filter to riskEngine address to avoid matching vault events
        vm.expectEmit(true, false, false, true, address(riskEngine));
        emit RiskEngine.RiskScoreWarning(90, 75, true);
        riskEngine.onReport(metadata, report);
    }

    function test_riskEngine_updatesAllocations() public {
        Allocation[] memory allocs = new Allocation[](1);
        allocs[0] = Allocation({protocol: "aave-v3", percentageBps: 10_000, apyBps: 500});

        RiskReport memory rr = RiskReport({
            riskScore: 55,
            confidence: 80,
            reasoningHash: bytes32(uint256(1)),
            allocations: allocs
        });

        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = abi.encode(rr);

        vm.prank(forwarder);
        riskEngine.onReport(metadata, report);

        assertEq(vault.updateAllocationsCallCount(), 1);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    REBASE EXECUTOR
    // ═══════════════════════════════════════════════════════════════

    function test_rebaseExec_processesValidFactor() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRebaseReport(1.005e18, 50, 500, 300);

        vm.prank(forwarder);
        rebaseExecutor.onReport(metadata, report);

        assertEq(vault.lastRebaseFactor(), 1.005e18);
        assertEq(vault.triggerRebaseCallCount(), 1);
    }

    function test_rebaseExec_rejectsFactorBelowMin() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRebaseReport(0.98e18, 50, 500, 300); // below MIN 0.99e18

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.RebaseFactorOutOfBounds.selector,
                0.98e18,
                RiskMath.MIN_REBASE_FACTOR,
                RiskMath.MAX_REBASE_FACTOR
            )
        );
        rebaseExecutor.onReport(metadata, report);
    }

    function test_rebaseExec_rejectsFactorAboveMax() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRebaseReport(1.02e18, 50, 500, 300); // above MAX 1.01e18

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.RebaseFactorOutOfBounds.selector,
                1.02e18,
                RiskMath.MIN_REBASE_FACTOR,
                RiskMath.MAX_REBASE_FACTOR
            )
        );
        rebaseExecutor.onReport(metadata, report);
    }

    function test_rebaseExec_acceptsBoundaryFactors() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);

        // MIN boundary
        bytes memory report1 = _buildRebaseReport(RiskMath.MIN_REBASE_FACTOR, 50, 500, 300);
        vm.prank(forwarder);
        rebaseExecutor.onReport(metadata, report1);
        assertEq(vault.lastRebaseFactor(), RiskMath.MIN_REBASE_FACTOR);

        // MAX boundary
        bytes memory report2 = _buildRebaseReport(RiskMath.MAX_REBASE_FACTOR, 50, 500, 300);
        vm.prank(forwarder);
        rebaseExecutor.onReport(metadata, report2);
        assertEq(vault.lastRebaseFactor(), RiskMath.MAX_REBASE_FACTOR);
    }

    function test_rebaseExec_pauseCheck_revertsWhenPaused() public {
        pausable.setPaused(true);

        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildRebaseReport(1.005e18, 50, 500, 300);

        vm.prank(forwarder);
        vm.expectRevert(OszillorErrors.SystemPaused.selector);
        rebaseExecutor.onReport(metadata, report);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    EVENT SENTINEL
    // ═══════════════════════════════════════════════════════════════

    function test_sentinel_triggersEmergency() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildThreatReport(true, 2 hours);

        vm.prank(forwarder);
        eventSentinel.onReport(metadata, report);

        assertTrue(vault.emergencyMode());
        assertEq(vault.emergencyDeRiskCallCount(), 1);
    }

    function test_sentinel_capsDurationAt4Hours() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildThreatReport(true, 10 hours); // exceeds max

        vm.prank(forwarder);
        eventSentinel.onReport(metadata, report);

        // Duration capped to 4 hours
        assertTrue(vault.emergencyMode());
        assertEq(vault.emergencyExpiry(), block.timestamp + 4 hours);
    }

    function test_sentinel_defaultsDurationTo1Hour() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildThreatReport(true, 0); // zero duration

        vm.prank(forwarder);
        eventSentinel.onReport(metadata, report);

        assertEq(vault.emergencyExpiry(), block.timestamp + 1 hours);
    }

    function test_sentinel_nonEmergency_doesNotTrigger() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, workflowOwner);
        bytes memory report = _buildThreatReport(false, 0);

        vm.prank(forwarder);
        eventSentinel.onReport(metadata, report);

        assertFalse(vault.emergencyMode());
        assertEq(vault.emergencyDeRiskCallCount(), 0);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    OSZILLOR FEES
    // ═══════════════════════════════════════════════════════════════

    function test_fees_initSetsDefaults() public view {
        assertEq(fees.feeRateBps(), 50); // 0.5% annual
        assertEq(fees.feeRecipient(), feeRecipient);
        assertEq(fees.accruedFees(), 0);
    }

    function test_fees_initRevertsZeroRecipient() public {
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        new ConcreteOszillorFees(address(usdc), address(0));
    }

    function test_fees_accruesOverTime() public {
        uint256 totalAssets = 1_000_000e6; // 1M USDC

        // Warp 1 year
        vm.warp(block.timestamp + 365.25 days);

        uint256 expected = fees.calculateAccruedFee(totalAssets);
        // 0.5% of 1M = 5000 USDC
        assertApproxEqAbs(expected, 5000e6, 1e6); // within 1 USDC tolerance
    }

    function test_fees_collectFeeUpdatesAccumulator() public {
        uint256 totalAssets = 1_000_000e6;

        vm.warp(block.timestamp + 365.25 days);
        fees.collectFeeIfDue(totalAssets);

        assertGt(fees.accruedFees(), 0);
        assertApproxEqAbs(fees.accruedFees(), 5000e6, 1e6);
    }

    function test_fees_withdrawOnlyTransfersAccrued() public {
        uint256 totalAssets = 1_000_000e6;
        // Fund the fees contract with USDC (simulating vault balance)
        usdc.mint(address(fees), 1_000_000e6);

        vm.warp(block.timestamp + 365.25 days);
        fees.collectFeeIfDue(totalAssets);

        uint256 accrued = fees.accruedFees();
        assertGt(accrued, 0);

        uint256 recipientBefore = usdc.balanceOf(feeRecipient);
        fees.withdrawFees();

        // Only accrued fees transferred, not full balance
        assertEq(usdc.balanceOf(feeRecipient), recipientBefore + accrued);
        assertEq(fees.accruedFees(), 0);
        // Contract still holds the rest
        assertGt(usdc.balanceOf(address(fees)), 0);
    }

    function test_fees_withdrawRevertsIfZero() public {
        vm.expectRevert(OszillorErrors.ZeroAmount.selector);
        fees.withdrawFees();
    }

    function test_fees_setRateRevertsAboveCap() public {
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.FeeTooHigh.selector, 201, 200)
        );
        fees.setFeeRate(201, 1_000_000e6);
    }

    function test_fees_setRateCollectsPendingFirst() public {
        uint256 totalAssets = 1_000_000e6;
        vm.warp(block.timestamp + 180 days);

        // Changing rate should collect at old rate first
        fees.setFeeRate(100, totalAssets);
        assertGt(fees.accruedFees(), 0);
        assertEq(fees.feeRateBps(), 100);
    }

    function test_fees_zeroElapsed_noAccrual() public view {
        // No time passed since init
        uint256 fee = fees.calculateAccruedFee(1_000_000e6);
        assertEq(fee, 0);
    }

    function test_fees_zeroAssets_noAccrual() public {
        vm.warp(block.timestamp + 365 days);
        uint256 fee = fees.calculateAccruedFee(0);
        assertEq(fee, 0);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    RISK REGISTRY
    // ═══════════════════════════════════════════════════════════════

    function test_registry_registerAdapter() public {
        address adapter = makeAddr("adapter1");
        bytes32 protocolId = keccak256("aave-v3");

        vm.prank(admin);
        registry.registerAdapter(protocolId, adapter);

        assertEq(registry.getAdapter(protocolId), adapter);
        assertEq(registry.registeredCount(), 1);
    }

    function test_registry_registerRevertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        registry.registerAdapter(keccak256("test"), address(0));
    }

    function test_registry_removeAdapter() public {
        address adapter = makeAddr("adapter1");
        bytes32 protocolId = keccak256("aave-v3");

        vm.prank(admin);
        registry.registerAdapter(protocolId, adapter);

        vm.prank(admin);
        registry.removeAdapter(protocolId);

        assertEq(registry.getAdapter(protocolId), address(0));
    }

    function test_registry_removeRevertsIfNotRegistered() public {
        vm.prank(admin);
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        registry.removeAdapter(keccak256("nonexistent"));
    }

    function test_registry_onlyOwnerCanRegister() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.registerAdapter(keccak256("test"), makeAddr("adapter"));
    }

    function test_registry_updateExistingAdapter() public {
        bytes32 protocolId = keccak256("aave-v3");
        address adapter1 = makeAddr("adapter1");
        address adapter2 = makeAddr("adapter2");

        vm.startPrank(admin);
        registry.registerAdapter(protocolId, adapter1);
        registry.registerAdapter(protocolId, adapter2);
        vm.stopPrank();

        assertEq(registry.getAdapter(protocolId), adapter2);
        // Count should still be 1 (updated, not new)
        assertEq(registry.registeredCount(), 1);
    }

    // ═══════════════════════════════════════════════════════════════
    //                    HELPERS
    // ═══════════════════════════════════════════════════════════════

    /// @dev Builds CRE metadata matching KeystoneFeedDefaultMetadataLib layout.
    ///      Layout: workflow_cid (32) | workflow_name (10) | workflow_owner (20) | report_name (2)
    function _buildMetadata(
        bytes32 wfId,
        bytes10 wfName,
        address wfOwner
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(wfId, wfName, wfOwner, bytes2(0));
    }

    function _buildRiskReport(
        uint256 score,
        uint256 confidence,
        bytes32 reasoningHash
    ) internal pure returns (bytes memory) {
        Allocation[] memory allocs = new Allocation[](0);
        RiskReport memory rr = RiskReport({
            riskScore: score,
            confidence: confidence,
            reasoningHash: reasoningHash,
            allocations: allocs
        });
        return abi.encode(rr);
    }

    function _buildRebaseReport(
        uint256 factor,
        uint256 riskScore,
        uint256 weightedApyBps,
        uint256 timeDelta
    ) internal pure returns (bytes memory) {
        // v2: RebaseExecutor now decodes RebalanceReport (adds targetEthPct)
        RebalanceReport memory rr = RebalanceReport({
            rebaseFactor: factor,
            currentRiskScore: riskScore,
            targetEthPct: 10_000, // default 100% ETH for existing tests
            weightedApyBps: weightedApyBps,
            timeDelta: timeDelta
        });
        return abi.encode(rr);
    }

    function _buildThreatReport(
        bool emergencyHalt,
        uint256 suggestedDuration
    ) internal pure returns (bytes memory) {
        ThreatReport memory tr = ThreatReport({
            level: RiskLevel.CRITICAL,
            threatType: keccak256("depeg"),
            riskAdjustment: 30,
            emergencyHalt: emergencyHalt,
            suggestedDuration: suggestedDuration,
            reason: "USDC depeg detected"
        });
        return abi.encode(tr);
    }
}
