// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title MockPausable
/// @notice Minimal pausable contract for testing pause checks in CRE receivers.
contract MockPausable is Pausable {
    function setPaused(bool _paused) external {
        if (_paused) _pause();
        else _unpause();
    }
}
