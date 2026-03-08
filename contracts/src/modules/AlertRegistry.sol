// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CREReceiver} from "./CREReceiver.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {AlertRule, AlertCondition, AlertReport} from "../libraries/DataStructures.sol";

/// @title AlertRegistry
/// @author Hitesh (vyqno)
/// @notice CRE W4 receiver that stores alert subscriptions from the x402 Risk Intelligence API.
/// @dev Deployed on Base Sepolia. Receives ABI-encoded AlertReport from the CRE HTTP trigger.
///      The CRE cron trigger reads active rules via view functions to evaluate alert conditions
///      against OszillorVault risk state on Ethereum Sepolia (cross-chain EVM reads).
///
///      Flow: AI Agent → x402 payment → Express API → CRE W4 HTTP trigger → onReport() → storage
///            CRE W4 Cron → getAllRuleIds() + getRule() → evaluate against vault → log triggered alerts
contract AlertRegistry is CREReceiver, Ownable {
    using SafeERC20 for IERC20;

    // ──────────────────── State ────────────────────

    /// @notice USDC token on Base Sepolia for revenue withdrawal.
    IERC20 public immutable USDC;

    /// @notice Monotonically increasing rule ID counter.
    uint256 public nextRuleId;

    /// @notice Mapping from rule ID to alert rule.
    mapping(uint256 => AlertRule) private _rules;

    /// @notice Array of all rule IDs (including expired/inactive) for enumeration.
    uint256[] private _ruleIds;

    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a new alert rule is created via CRE report.
    event AlertCreated(
        uint256 indexed ruleId,
        address indexed subscriber,
        AlertCondition condition,
        uint256 threshold,
        string webhookUrl,
        uint256 ttl
    );

    /// @notice Emitted when USDC revenue is withdrawn by the owner.
    event UsdcWithdrawn(address indexed to, uint256 amount);

    // ──────────────────── Constructor ────────────────────

    /// @notice Constructs the AlertRegistry with USDC address and CRE validation params.
    /// @param usdc USDC token address on Base Sepolia.
    /// @param owner_ Contract owner (can withdraw USDC revenue).
    /// @param forwarder Authorized CRE forwarder (KeystoneForwarder) address.
    /// @param workflowId Expected CRE workflow CID (bytes32).
    /// @param workflowName Expected CRE workflow name (bytes10).
    /// @param workflowOwner Expected CRE workflow owner address.
    constructor(
        address usdc,
        address owner_,
        address forwarder,
        bytes32 workflowId,
        bytes10 workflowName,
        address workflowOwner
    ) CREReceiver(forwarder, workflowId, workflowName, workflowOwner) Ownable(owner_) {
        if (usdc == address(0)) revert OszillorErrors.ZeroAddress();
        USDC = IERC20(usdc);
    }

    // ──────────────────── CRE Report Handler ────────────────────

    /// @notice Processes a validated CRE W4 report containing an alert subscription.
    /// @dev Called by CREReceiver.onReport() after 4-check validation passes.
    ///      Decodes AlertReport, validates fields, stores the rule, and emits event.
    /// @param report ABI-encoded AlertReport payload.
    function _handleReport(bytes calldata report) internal override {
        AlertReport memory alertReport = abi.decode(report, (AlertReport));

        // Validate condition type (0=RISK_ABOVE, 1=RISK_BELOW, 2=EMERGENCY)
        if (alertReport.condition > 2) {
            revert OszillorErrors.InvalidAlertCondition(alertReport.condition);
        }

        // Validate threshold for risk-based conditions
        if (alertReport.condition != uint8(AlertCondition.EMERGENCY) && alertReport.threshold > 100) {
            revert OszillorErrors.InvalidAlertThreshold(alertReport.threshold);
        }

        // Validate webhook URL is not empty
        if (bytes(alertReport.webhookUrl).length == 0) {
            revert OszillorErrors.EmptyWebhookUrl();
        }

        uint256 ruleId = nextRuleId++;

        _rules[ruleId] = AlertRule({
            subscriber: alertReport.subscriber,
            condition: AlertCondition(alertReport.condition),
            threshold: alertReport.threshold,
            webhookUrl: alertReport.webhookUrl,
            createdAt: block.timestamp,
            ttl: alertReport.ttl,
            active: true
        });

        _ruleIds.push(ruleId);

        emit AlertCreated(
            ruleId,
            alertReport.subscriber,
            AlertCondition(alertReport.condition),
            alertReport.threshold,
            alertReport.webhookUrl,
            alertReport.ttl
        );
    }

    // ──────────────────── View Functions ────────────────────

    /// @notice Returns the alert rule for the given ID.
    /// @param ruleId The rule ID to look up.
    /// @return The AlertRule struct.
    function getRule(uint256 ruleId) external view returns (AlertRule memory) {
        if (ruleId >= nextRuleId) {
            revert OszillorErrors.AlertRuleNotFound(ruleId);
        }
        return _rules[ruleId];
    }

    /// @notice Returns all rule IDs for enumeration by the CRE cron trigger.
    /// @return Array of all rule IDs (caller should check isRuleActive for each).
    function getAllRuleIds() external view returns (uint256[] memory) {
        return _ruleIds;
    }

    /// @notice Checks if a rule is currently active (not expired).
    /// @param ruleId The rule ID to check.
    /// @return True if the rule exists, is active, and has not expired.
    function isRuleActive(uint256 ruleId) external view returns (bool) {
        if (ruleId >= nextRuleId) return false;
        AlertRule storage rule = _rules[ruleId];
        if (!rule.active) return false;
        // TTL of 0 means no expiry
        if (rule.ttl > 0 && block.timestamp > rule.createdAt + rule.ttl) return false;
        return true;
    }

    /// @notice Returns the total number of rules created.
    function ruleCount() external view returns (uint256) {
        return nextRuleId;
    }

    // ──────────────────── Owner Functions ────────────────────

    /// @notice Withdraws accumulated USDC revenue to a specified address.
    /// @dev Only callable by the contract owner. The x402 facilitator deposits USDC
    ///      directly to this contract as payment for alert subscriptions.
    /// @param to Recipient address for the USDC withdrawal.
    /// @param amount Amount of USDC to withdraw (use type(uint256).max for full balance).
    function withdrawUsdc(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert OszillorErrors.ZeroAddress();
        uint256 balance = USDC.balanceOf(address(this));
        uint256 transferAmount = amount > balance ? balance : amount;
        if (transferAmount == 0) revert OszillorErrors.ZeroAmount();
        USDC.safeTransfer(to, transferAmount);
        emit UsdcWithdrawn(to, transferAmount);
    }
}
