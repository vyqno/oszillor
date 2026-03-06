// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {CREReceiver} from "./CREReceiver.sol";
import {IOszillorVault} from "../interfaces/IOszillorVault.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {RiskMath} from "../libraries/RiskMath.sol";
import {RebalanceReport} from "../libraries/DataStructures.sol";

/// @title RebaseExecutor
/// @author Hitesh (vyqno)
/// @notice CRE W3 receiver — applies rebase factors to the vault's token.
/// @dev Extends CREReceiver. Reads current risk state from vault, validates factor
///      bounds via RiskMath, and calls vault.triggerRebase(). Includes whenNotPaused
///      check (HIGH-08 fix).
contract RebaseExecutor is CREReceiver {
    // ──────────────────── Events ────────────────────

    /// @notice Emitted when a rebalance + rebase report is processed.
    /// @param factor The rebase factor applied.
    /// @param targetEthPct Target ETH allocation in bps.
    /// @param riskScore Risk score at time of rebase.
    event RebalanceReportProcessed(uint256 factor, uint256 targetEthPct, uint256 riskScore);

    // ──────────────────── State ────────────────────

    /// @notice Reference to the OszillorVault for typed interface calls.
    IOszillorVault public immutable vault;

    /// @notice External pause check address.
    address public immutable pauseChecker;

    /// @notice Constructs the RebaseExecutor with vault reference and CRE params.
    /// @param _vault Address of the OszillorVault contract.
    /// @param _pauseChecker Address of the pausable contract.
    /// @param _forwarder CRE forwarder address.
    /// @param _workflowId CRE workflow CID.
    /// @param _workflowName CRE workflow name.
    /// @param _workflowOwner CRE workflow owner.
    constructor(
        address _vault,
        address _pauseChecker,
        address _forwarder,
        bytes32 _workflowId,
        bytes10 _workflowName,
        address _workflowOwner
    ) CREReceiver(_forwarder, _workflowId, _workflowName, _workflowOwner) {
        vault = IOszillorVault(_vault);
        pauseChecker = _pauseChecker;
    }

    /// @notice Processes a validated W3 rebalance + rebase report.
    /// @dev Validates factor bounds, checks pause state, then calls vault.rebalance()
    ///      followed by vault.triggerRebase(). Rebalance adjusts ETH/USDC ratio first,
    ///      then rebase adjusts the token index based on NAV change.
    /// @param report ABI-encoded RebalanceReport struct.
    function _handleReport(bytes calldata report) internal override {
        // HIGH-08: Check pause state
        _requireNotPaused();

        // Decode the v2 report
        RebalanceReport memory r = abi.decode(report, (RebalanceReport));

        // Validate factor bounds (CRIT-02 fix enforced here and in token)
        if (
            r.rebaseFactor < RiskMath.MIN_REBASE_FACTOR
                || r.rebaseFactor > RiskMath.MAX_REBASE_FACTOR
        ) {
            revert OszillorErrors.RebaseFactorOutOfBounds(
                r.rebaseFactor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR
            );
        }

        // Step 1: Rebalance portfolio (adjust ETH/USDC ratio)
        vault.rebalance(r.targetEthPct);

        // Step 2: Trigger rebase (adjust token index based on NAV change)
        vault.triggerRebase(r.rebaseFactor);

        emit RebalanceReportProcessed(r.rebaseFactor, r.targetEthPct, r.currentRiskScore);
    }

    /// @notice Checks that the pause-checker contract is not paused.
    /// @dev Uses typed Pausable interface — never raw staticcall.
    function _requireNotPaused() internal view {
        if (Pausable(pauseChecker).paused()) {
            revert OszillorErrors.SystemPaused();
        }
    }
}
