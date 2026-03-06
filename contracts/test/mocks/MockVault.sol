// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IOszillorVault} from "../../src/interfaces/IOszillorVault.sol";
import {RiskLevel, RiskState, Allocation} from "../../src/libraries/DataStructures.sol";
import {RiskMath} from "../../src/libraries/RiskMath.sol";

/// @title MockVault
/// @notice Minimal mock of IOszillorVault for testing CRE receiver modules.
contract MockVault is IOszillorVault {
    uint256 public override currentRiskScore;
    RiskState internal _riskState;
    bool public override emergencyMode;
    uint256 public emergencyExpiry;
    Allocation[] internal _allocations;
    uint256 public lastRebaseFactor;

    // Track calls for assertions
    uint256 public updateRiskScoreCallCount;
    uint256 public updateAllocationsCallCount;
    uint256 public triggerRebaseCallCount;
    uint256 public emergencyDeRiskCallCount;

    constructor() {
        // CRIT-03: Initialize to CAUTION
        currentRiskScore = 50;
        _riskState = RiskState({
            riskScore: 50,
            confidence: 0,
            timestamp: block.timestamp,
            reasoningHash: bytes32(0)
        });
    }

    function deposit(uint256) external pure returns (uint256) { return 0; }
    function withdraw(uint256) external pure returns (uint256) { return 0; }

    function updateRiskScore(uint256 score, uint256 confidence, bytes32 reasoningHash) external override {
        currentRiskScore = score;
        _riskState = RiskState({
            riskScore: score,
            confidence: confidence,
            timestamp: block.timestamp,
            reasoningHash: reasoningHash
        });
        updateRiskScoreCallCount++;
    }

    function updateAllocations(Allocation[] calldata allocs) external override {
        delete _allocations;
        for (uint256 i = 0; i < allocs.length; i++) {
            _allocations.push(allocs[i]);
        }
        updateAllocationsCallCount++;
    }

    function triggerRebase(uint256 factor) external override {
        lastRebaseFactor = factor;
        triggerRebaseCallCount++;
    }

    function emergencyDeRisk(string calldata, uint256 duration) external override {
        emergencyMode = true;
        emergencyExpiry = block.timestamp + duration;
        emergencyDeRiskCallCount++;
    }

    function exitEmergencyMode() external override {
        emergencyMode = false;
        emergencyExpiry = 0;
    }

    function riskState() external view override returns (RiskState memory) { return _riskState; }
    function totalAssets() external pure override returns (uint256) { return 1_000_000e6; }
    function internalTotalAssets() external pure override returns (uint256) { return 1_000_000e6; }
    function riskLevel() external view override returns (RiskLevel) { return RiskMath.riskLevel(currentRiskScore); }
    function getAllocations() external view override returns (Allocation[] memory) { return _allocations; }
    function maxDeposit(address) external pure override returns (uint256) { return type(uint256).max; }
    function maxWithdraw(address) external pure override returns (uint256) { return 0; }

    // v2: Strategy integration
    uint256 public lastRebalanceTarget;
    uint256 public rebalanceCallCount;

    function rebalance(uint256 targetEthPct) external override {
        lastRebalanceTarget = targetEthPct;
        rebalanceCallCount++;
    }

    function totalNav() external pure override returns (uint256) { return 1_000_000e18; }

    // Helper to set score for testing delta clamp
    function setRiskScore(uint256 score) external { currentRiskScore = score; }
}
