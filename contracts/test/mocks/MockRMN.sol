// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRMN} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRMN.sol";

/// @title MockRMN
/// @notice Mock RMN proxy for testing CCIP token pool.
contract MockRMN is IRMN {
    bool private _cursed;
    mapping(bytes16 => bool) private _subjectCursed;

    function isBlessed(TaggedRoot calldata) external pure returns (bool) {
        return true;
    }

    function isCursed() external view returns (bool) {
        return _cursed;
    }

    function isCursed(bytes16 subject) external view returns (bool) {
        return _cursed || _subjectCursed[subject];
    }

    // ── Test helpers ──
    function setCursed(bool cursed) external {
        _cursed = cursed;
    }

    function setSubjectCursed(bytes16 subject, bool cursed) external {
        _subjectCursed[subject] = cursed;
    }
}
