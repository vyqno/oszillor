// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OszillorVault} from "../../src/core/OszillorVault.sol";

/// @title OszillorVaultHarness
/// @notice Certora harness — exposes internal state for formal verification.
/// @dev NEVER deployed in production. Only used by the Certora Prover.
contract OszillorVaultHarness is OszillorVault {
    constructor(
        address _asset,
        address _token,
        address _riskEngine,
        address _rebaseExecutor,
        address _sentinel,
        address _admin,
        address _feeRecipient
    ) OszillorVault(_asset, _token, _riskEngine, _rebaseExecutor, _sentinel, _admin, _feeRecipient) {}

    // ─── Expose external views as harness wrappers for Certora ───

    function getInternalTotalAssets() external view returns (uint256) {
        return this.internalTotalAssets();
    }

    function getRiskScore() external view returns (uint256) {
        return this.currentRiskScore();
    }

    function isEmergencyModeRaw() external view returns (bool) {
        return this.emergencyMode();
    }
}
