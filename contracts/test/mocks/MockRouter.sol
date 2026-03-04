// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouter} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouter.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/// @title MockRouter
/// @notice Mock CCIP Router for testing token pool on/offRamp validation.
contract MockRouter is IRouter {
    mapping(uint64 => address) private _onRamps;
    mapping(uint64 => mapping(address => bool)) private _offRamps;

    function routeMessage(
        Client.Any2EVMMessage calldata,
        uint16,
        uint256,
        address
    ) external pure returns (bool, bytes memory, uint256) {
        return (true, "", 0);
    }

    function getOnRamp(uint64 destChainSelector) external view returns (address) {
        return _onRamps[destChainSelector];
    }

    function isOffRamp(uint64 sourceChainSelector, address offRamp) external view returns (bool) {
        return _offRamps[sourceChainSelector][offRamp];
    }

    // ── Test helpers ──
    function setOnRamp(uint64 chainSelector, address onRamp) external {
        _onRamps[chainSelector] = onRamp;
    }

    function setOffRamp(uint64 chainSelector, address offRamp, bool enabled) external {
        _offRamps[chainSelector][offRamp] = enabled;
    }
}
