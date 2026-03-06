// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OszillorPeer} from "./OszillorPeer.sol";
import {ISpokePeer} from "../interfaces/ISpokePeer.sol";
import {CcipMessageType, RiskStateSync, RiskLevel} from "../libraries/DataStructures.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {Roles} from "../libraries/Roles.sol";

/// @title SpokePeer
/// @author Hitesh (vyqno)
/// @notice Spoke-chain CCIP peer contract.
contract SpokePeer is OszillorPeer, ISpokePeer {
    uint256 public override lastHubUpdate;
    uint256 public override lastProcessedNonce;
    uint256 public override lastReceivedRebaseIndex;
    uint64 public override hubChainSelector;
    
    uint256 public override maxSpokeStaleness = 15 minutes;
    uint256 public override maxIndexDivergenceBps = 500; // 5%

    uint256 private _currentRiskScore;
    bool private _emergencyMode;

    constructor(
        address router,
        address _feeToken,
        address admin,
        address feeRecipient,
        uint64 _hubChainSelector
    ) OszillorPeer(router, _feeToken, admin, feeRecipient) {
        hubChainSelector = _hubChainSelector;
    }

    function setMaxSpokeStaleness(uint256 _maxStaleness) external onlyRole(Roles.CROSS_CHAIN_ADMIN_ROLE) {
        maxSpokeStaleness = _maxStaleness;
    }

    function setMaxIndexDivergence(uint256 _maxDivergenceBps) external onlyRole(Roles.CROSS_CHAIN_ADMIN_ROLE) {
        maxIndexDivergenceBps = _maxDivergenceBps;
    }

    function isStateStale() public view override returns (bool) {
        return (block.timestamp - lastHubUpdate) > maxSpokeStaleness;
    }

    function spokeRiskLevel() external view override returns (RiskLevel) {
        uint256 score = _currentRiskScore;
        if (score >= 90) return RiskLevel.CRITICAL;
        if (score >= 70) return RiskLevel.DANGER;
        if (score >= 40) return RiskLevel.CAUTION;
        return RiskLevel.SAFE;
    }

    // ──────────────────── Enforcement (CRIT-04 + MED-01) ────────────────────

    /// @inheritdoc ISpokePeer
    function checkDepositAllowed() external view override {
        if (isStateStale()) {
            revert OszillorErrors.RiskStateTooStale(
                block.timestamp - lastHubUpdate,
                maxSpokeStaleness
            );
        }
        if (_emergencyMode) {
            revert OszillorErrors.EmergencyModeActive();
        }
    }

    /// @inheritdoc ISpokePeer
    function checkWithdrawalAllowed(uint256 localRebaseIndex) external view override {
        if (lastReceivedRebaseIndex == 0) return; // No hub data yet, allow

        uint256 hubIndex = lastReceivedRebaseIndex;
        uint256 diff = localRebaseIndex > hubIndex
            ? localRebaseIndex - hubIndex
            : hubIndex - localRebaseIndex;
        uint256 divergenceBps = (diff * 10_000) / hubIndex;

        if (divergenceBps > maxIndexDivergenceBps) {
            revert OszillorErrors.IndexDivergenceTooHigh(divergenceBps, maxIndexDivergenceBps);
        }
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override onlyAllowedPeer(message.sourceChainSelector, abi.decode(message.sender, (address))) {
        CcipMessageType messageType = abi.decode(message.data, (CcipMessageType));
        
        if (messageType == CcipMessageType.RISK_STATE_SYNC) {
            // Skips type first 32 bytes
            (, RiskStateSync memory stateSync) = abi.decode(message.data, (CcipMessageType, RiskStateSync));
            
            // MED-03 fix: Nonce-based replay protection
            if (stateSync.nonce <= lastProcessedNonce) {
                revert OszillorErrors.ReplayDetected(stateSync.nonce, lastProcessedNonce);
            }
            
            // MED-02 fix: Timestamp staleness check
            if (block.timestamp > stateSync.timestamp + 5 minutes) {
                revert OszillorErrors.MessageTooOld(stateSync.timestamp, 5 minutes);
            }
            
            lastProcessedNonce = stateSync.nonce;
            lastHubUpdate = block.timestamp;
            lastReceivedRebaseIndex = stateSync.rebaseIndex;
            _currentRiskScore = stateSync.riskScore;
            _emergencyMode = stateSync.emergencyMode;

            emit RiskStateSynced(
                stateSync.nonce,
                stateSync.riskScore,
                stateSync.rebaseIndex,
                stateSync.emergencyMode
            );
        } else {
            // MED-08 fix: Revert on unknown message types (NEVER silently ignore)
            revert OszillorErrors.UnknownMessageType(uint8(messageType));
        }
    }
}
