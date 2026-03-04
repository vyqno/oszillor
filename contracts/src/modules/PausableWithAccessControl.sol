// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Roles} from "../libraries/Roles.sol";

/// @title PausableWithAccessControl
/// @author Hitesh (vyqno)
/// @notice Combines OZ Pausable + AccessControlDefaultAdminRules + AccessControlEnumerable.
/// @dev 5-day admin transfer delay (LOW-01). Separate pause/unpause roles.
///
///      C3 Linearization order:
///        PausableWithAccessControl
///        → AccessControlEnumerable → AccessControlDefaultAdminRules
///        → AccessControl → Context, IAccessControl, ERC165
///
///      Every function overridden in multiple parents must be resolved here.
abstract contract PausableWithAccessControl is
    AccessControlDefaultAdminRules,
    AccessControlEnumerable,
    Pausable
{
    constructor(
        address admin
    ) AccessControlDefaultAdminRules(5 days, admin) {}

    // ──────────────────── Pause / Unpause ────────────────────

    /// @notice Pauses the contract. Only EMERGENCY_PAUSER_ROLE.
    function emergencyPause() external onlyRole(Roles.EMERGENCY_PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract. Only EMERGENCY_UNPAUSER_ROLE.
    function emergencyUnpause() external onlyRole(Roles.EMERGENCY_UNPAUSER_ROLE) {
        _unpause();
    }

    // ──────────────────── Diamond Resolution ────────────────────

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(AccessControlDefaultAdminRules, AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function grantRole(bytes32 role, address account)
        public
        virtual
        override(IAccessControl, AccessControl, AccessControlDefaultAdminRules)
    {
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account)
        public
        virtual
        override(IAccessControl, AccessControl, AccessControlDefaultAdminRules)
    {
        super.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account)
        public
        virtual
        override(IAccessControl, AccessControl, AccessControlDefaultAdminRules)
    {
        super.renounceRole(role, account);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole)
        internal
        virtual
        override(AccessControl, AccessControlDefaultAdminRules)
    {
        super._setRoleAdmin(role, adminRole);
    }

    function _grantRole(bytes32 role, address account)
        internal
        virtual
        override(AccessControlDefaultAdminRules, AccessControlEnumerable)
        returns (bool)
    {
        return super._grantRole(role, account);
    }

    function _revokeRole(bytes32 role, address account)
        internal
        virtual
        override(AccessControlDefaultAdminRules, AccessControlEnumerable)
        returns (bool)
    {
        return super._revokeRole(role, account);
    }
}
