// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OszillorToken} from "../../src/core/OszillorToken.sol";

/// @title OszillorTokenHarness
/// @notice Certora harness — exposes internal state for formal verification.
/// @dev NEVER deployed in production. Only used by the Certora Prover.
///      Uses `this.` to call external view functions from the parent contract.
contract OszillorTokenHarness is OszillorToken {
    constructor(
        string memory name_,
        string memory symbol_,
        address admin
    ) OszillorToken(name_, symbol_, admin) {}

    // ─── Expose external views as harness wrappers for Certora ───

    function getShares(address account) external view returns (uint256) {
        return this.sharesOf(account);
    }

    function getRebaseIndex() external view returns (uint256) {
        return this.rebaseIndex();
    }

    function getTotalShares() external view returns (uint256) {
        return this.totalShares();
    }

    function getShareAllowance(address owner, address spender) external view returns (uint256) {
        return this.shareAllowance(owner, spender);
    }

    function getEpoch() external view returns (uint256) {
        return this.epoch();
    }
}
