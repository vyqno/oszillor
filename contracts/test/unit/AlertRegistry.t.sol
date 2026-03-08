// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {OszillorErrors} from "../../src/libraries/OszillorErrors.sol";
import {AlertRule, AlertCondition, AlertReport} from "../../src/libraries/DataStructures.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {AlertRegistry} from "../../src/modules/AlertRegistry.sol";

/// @title AlertRegistryTest
/// @author Hitesh (vyqno)
/// @notice Unit tests for the AlertRegistry CRE W4 receiver.
contract AlertRegistryTest is Test {
    // ──────────────────── Actors ────────────────────
    address admin = makeAddr("admin");
    address attacker = makeAddr("attacker");
    address subscriber = makeAddr("subscriber");
    address forwarder = makeAddr("forwarder");
    address workflowOwner = makeAddr("workflowOwner");
    address treasury = makeAddr("treasury");

    bytes32 workflowId = keccak256("test-w4-workflow");
    bytes10 workflowName = bytes10(keccak256("w4-alerts"));

    // ──────────────────── Contracts ────────────────────
    MockERC20 usdc;
    AlertRegistry registry;

    function setUp() public {
        vm.warp(1_700_000_000);
        vm.startPrank(admin);

        usdc = new MockERC20();
        registry = new AlertRegistry(
            address(usdc),
            admin,
            forwarder,
            workflowId,
            workflowName,
            workflowOwner
        );

        vm.stopPrank();
    }

    // ──────────────────── Helpers ────────────────────

    function _buildMetadata(
        bytes32 wfId,
        bytes10 wfName,
        address wfOwner
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(wfId, wfName, wfOwner, bytes2(0));
    }

    function _validMetadata() internal view returns (bytes memory) {
        return _buildMetadata(workflowId, workflowName, workflowOwner);
    }

    function _buildAlertReport(
        address sub,
        uint8 condition,
        uint256 threshold,
        string memory webhookUrl,
        uint256 ttl
    ) internal pure returns (bytes memory) {
        AlertReport memory report = AlertReport({
            subscriber: sub,
            condition: condition,
            threshold: threshold,
            webhookUrl: webhookUrl,
            ttl: ttl
        });
        return abi.encode(report);
    }

    // ═══════════════════════════════════════════════════════════════
    //               CRE 4-CHECK VALIDATION
    // ═══════════════════════════════════════════════════════════════

    function test_cre_rejectsWrongForwarder() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com", 3600);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.NotForwarder.selector, attacker, forwarder)
        );
        registry.onReport(metadata, report);
    }

    function test_cre_rejectsWrongWorkflowId() public {
        bytes32 wrongId = keccak256("wrong-workflow");
        bytes memory metadata = _buildMetadata(wrongId, workflowName, workflowOwner);
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com", 3600);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.WrongWorkflow.selector, wrongId, workflowId)
        );
        registry.onReport(metadata, report);
    }

    function test_cre_rejectsWrongOwner() public {
        bytes memory metadata = _buildMetadata(workflowId, workflowName, attacker);
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com", 3600);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.WrongOwner.selector, attacker, workflowOwner)
        );
        registry.onReport(metadata, report);
    }

    function test_cre_rejectsWrongName() public {
        bytes10 wrongName = bytes10(keccak256("wrong-name"));
        bytes memory metadata = _buildMetadata(workflowId, wrongName, workflowOwner);
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com", 3600);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.WrongName.selector,
                bytes32(wrongName),
                bytes32(workflowName)
            )
        );
        registry.onReport(metadata, report);
    }

    // ═══════════════════════════════════════════════════════════════
    //               ALERT CREATION (HAPPY PATH)
    // ═══════════════════════════════════════════════════════════════

    function test_alertCreation_riskAbove() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com/alert", 3600);

        vm.prank(forwarder);
        registry.onReport(metadata, report);

        assertEq(registry.nextRuleId(), 1);

        AlertRule memory rule = registry.getRule(0);
        assertEq(rule.subscriber, subscriber);
        assertEq(uint8(rule.condition), uint8(AlertCondition.RISK_ABOVE));
        assertEq(rule.threshold, 70);
        assertEq(rule.webhookUrl, "https://hook.example.com/alert");
        assertEq(rule.createdAt, block.timestamp);
        assertEq(rule.ttl, 3600);
        assertTrue(rule.active);
    }

    function test_alertCreation_emergency() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 2, 0, "https://hook.example.com/emergency", 0);

        vm.prank(forwarder);
        registry.onReport(metadata, report);

        AlertRule memory rule = registry.getRule(0);
        assertEq(uint8(rule.condition), uint8(AlertCondition.EMERGENCY));
        assertEq(rule.ttl, 0); // no expiry
    }

    function test_alertCreation_multipleRules() public {
        bytes memory metadata = _validMetadata();

        vm.startPrank(forwarder);
        registry.onReport(metadata, _buildAlertReport(subscriber, 0, 70, "https://a.com", 3600));
        registry.onReport(metadata, _buildAlertReport(subscriber, 1, 30, "https://b.com", 7200));
        registry.onReport(metadata, _buildAlertReport(subscriber, 2, 0, "https://c.com", 0));
        vm.stopPrank();

        assertEq(registry.nextRuleId(), 3);
        assertEq(registry.ruleCount(), 3);

        uint256[] memory ids = registry.getAllRuleIds();
        assertEq(ids.length, 3);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
        assertEq(ids[2], 2);
    }

    // ═══════════════════════════════════════════════════════════════
    //               VALIDATION REJECTIONS
    // ═══════════════════════════════════════════════════════════════

    function test_alertCreation_revertsInvalidCondition() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 3, 50, "https://hook.example.com", 3600);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.InvalidAlertCondition.selector, 3)
        );
        registry.onReport(metadata, report);
    }

    function test_alertCreation_revertsInvalidThreshold() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 0, 101, "https://hook.example.com", 3600);

        vm.prank(forwarder);
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.InvalidAlertThreshold.selector, 101)
        );
        registry.onReport(metadata, report);
    }

    function test_alertCreation_revertsEmptyWebhook() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "", 3600);

        vm.prank(forwarder);
        vm.expectRevert(OszillorErrors.EmptyWebhookUrl.selector);
        registry.onReport(metadata, report);
    }

    // ═══════════════════════════════════════════════════════════════
    //               TTL EXPIRY
    // ═══════════════════════════════════════════════════════════════

    function test_isRuleActive_trueWhenNotExpired() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com", 3600);

        vm.prank(forwarder);
        registry.onReport(metadata, report);

        assertTrue(registry.isRuleActive(0));
    }

    function test_isRuleActive_falseWhenExpired() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com", 3600);

        vm.prank(forwarder);
        registry.onReport(metadata, report);

        // Warp past TTL
        vm.warp(block.timestamp + 3601);

        assertFalse(registry.isRuleActive(0));
    }

    function test_isRuleActive_trueWhenNoExpiry() public {
        bytes memory metadata = _validMetadata();
        bytes memory report = _buildAlertReport(subscriber, 0, 70, "https://hook.example.com", 0);

        vm.prank(forwarder);
        registry.onReport(metadata, report);

        // Warp far into the future
        vm.warp(block.timestamp + 365 days);

        assertTrue(registry.isRuleActive(0));
    }

    function test_isRuleActive_falseForNonexistent() public view {
        assertFalse(registry.isRuleActive(999));
    }

    // ═══════════════════════════════════════════════════════════════
    //               USDC WITHDRAWAL
    // ═══════════════════════════════════════════════════════════════

    function test_withdrawUsdc_success() public {
        // Simulate x402 USDC revenue deposited to registry
        usdc.mint(address(registry), 1000e6);

        vm.prank(admin);
        registry.withdrawUsdc(treasury, 500e6);

        assertEq(usdc.balanceOf(treasury), 500e6);
        assertEq(usdc.balanceOf(address(registry)), 500e6);
    }

    function test_withdrawUsdc_revertsForNonOwner() public {
        usdc.mint(address(registry), 1000e6);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker)
        );
        registry.withdrawUsdc(treasury, 500e6);
    }

    function test_withdrawUsdc_revertsZeroAddress() public {
        usdc.mint(address(registry), 1000e6);

        vm.prank(admin);
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        registry.withdrawUsdc(address(0), 500e6);
    }

    function test_withdrawUsdc_revertsZeroBalance() public {
        vm.prank(admin);
        vm.expectRevert(OszillorErrors.ZeroAmount.selector);
        registry.withdrawUsdc(treasury, 500e6);
    }

    // ═══════════════════════════════════════════════════════════════
    //               VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════

    function test_getRule_revertsForNonexistent() public {
        vm.expectRevert(
            abi.encodeWithSelector(OszillorErrors.AlertRuleNotFound.selector, 0)
        );
        registry.getRule(0);
    }

    function test_constructor_revertsZeroUsdc() public {
        vm.expectRevert(OszillorErrors.ZeroAddress.selector);
        new AlertRegistry(
            address(0),
            admin,
            forwarder,
            workflowId,
            workflowName,
            workflowOwner
        );
    }
}
