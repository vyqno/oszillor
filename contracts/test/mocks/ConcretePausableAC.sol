// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {PausableWithAccessControl} from "../../src/modules/PausableWithAccessControl.sol";

/// @title ConcretePausableAC
/// @notice Concrete instantiation of PausableWithAccessControl for testing.
contract ConcretePausableAC is PausableWithAccessControl {
    constructor(address admin) PausableWithAccessControl(admin) {}
}
