// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IReceiver} from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";

/// @title CREReceiver
/// @author Hitesh (vyqno)
/// @notice Abstract base for all 3 CRE workflow receivers (RiskEngine, RebaseExecutor, EventSentinel).
/// @dev Validates the CRE 4-check security model using immutable workflow params (MED-03 fix).
///      Metadata layout (from Chainlink KeystoneForwarder):
///        - workflow_cid    (bytes32) at offset 0
///        - workflow_name   (bytes10) at offset 32
///        - workflow_owner  (address) at offset 42
///        - report_name     (bytes2)  at offset 62
///      Total metadata length: 64 bytes.
///      `msg.sender` is validated as the authorized forwarder.
abstract contract CREReceiver is IReceiver {
    /// @notice The authorized CRE forwarder address.
    address public immutable FORWARDER;

    /// @notice The expected workflow CID (content identifier).
    bytes32 public immutable WORKFLOW_ID;

    /// @notice The expected workflow name (10-byte identifier).
    bytes10 public immutable WORKFLOW_NAME;

    /// @notice The expected workflow owner address.
    address public immutable WORKFLOW_OWNER;

    /// @notice Constructs the CRE receiver with immutable workflow validation params.
    /// @dev All params are immutable — cannot be changed by any admin after deployment.
    ///      This prevents a compromised admin from redirecting reports to a rogue workflow.
    /// @param forwarder Authorized CRE forwarder (KeystoneForwarder) address.
    /// @param workflowId Expected workflow CID (bytes32).
    /// @param workflowName Expected workflow name (bytes10).
    /// @param workflowOwner Expected workflow owner address.
    constructor(
        address forwarder,
        bytes32 workflowId,
        bytes10 workflowName,
        address workflowOwner
    ) {
        FORWARDER = forwarder;
        WORKFLOW_ID = workflowId;
        WORKFLOW_NAME = workflowName;
        WORKFLOW_OWNER = workflowOwner;
    }

    /// @notice Entry point called by the CRE forwarder with validated reports.
    /// @dev Performs 4-check validation, then delegates to subclass via `_handleReport`.
    /// @param metadata ABI-packed CRE metadata (workflow_cid, name, owner, report_name).
    /// @param report The validated workflow report payload.
    function onReport(bytes calldata metadata, bytes calldata report) external override {
        _validateCREReport(metadata);
        _handleReport(report);
    }

    /// @notice Validates the CRE 4-check security model against immutable params.
    /// @dev Parses metadata using assembly to match Chainlink's `KeystoneFeedDefaultMetadataLib`.
    ///      Reverts with specific custom errors for each failed check.
    /// @param metadata The raw metadata bytes from the CRE forwarder.
    function _validateCREReport(bytes calldata metadata) internal view {
        // Check 1: Forwarder
        if (msg.sender != FORWARDER) {
            revert OszillorErrors.NotForwarder(msg.sender, FORWARDER);
        }

        // Parse metadata via assembly (matches KeystoneFeedDefaultMetadataLib layout)
        bytes32 workflowCid;
        bytes10 workflowName;
        address workflowOwner;

        assembly {
            // metadata is calldata, use calldataload with metadata.offset
            workflowCid := calldataload(metadata.offset)
            workflowName := calldataload(add(metadata.offset, 32))
            workflowOwner := shr(mul(12, 8), calldataload(add(metadata.offset, 42)))
        }

        // Check 2: Workflow ID
        if (workflowCid != WORKFLOW_ID) {
            revert OszillorErrors.WrongWorkflow(workflowCid, WORKFLOW_ID);
        }

        // Check 3: Workflow Owner
        if (workflowOwner != WORKFLOW_OWNER) {
            revert OszillorErrors.WrongOwner(workflowOwner, WORKFLOW_OWNER);
        }

        // Check 4: Workflow Name
        if (workflowName != WORKFLOW_NAME) {
            revert OszillorErrors.WrongName(bytes32(workflowName), bytes32(WORKFLOW_NAME));
        }
    }

    /// @notice Subclass hook — process the validated report payload.
    /// @dev Called after all 4 CRE checks pass. Override in RiskEngine,
    ///      RebaseExecutor, and EventSentinel.
    /// @param report The decoded report payload.
    function _handleReport(bytes calldata report) internal virtual;
}
