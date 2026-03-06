// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC677Receiver} from "../interfaces/IERC677Receiver.sol";
import {PausableWithAccessControl} from "../modules/PausableWithAccessControl.sol";
import {OszillorFees} from "../modules/OszillorFees.sol";
import {IOszillorPeer} from "../interfaces/IOszillorPeer.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {Roles} from "../libraries/Roles.sol";

/// @title OszillorPeer
/// @author Hitesh (vyqno)
/// @notice Abstract base contract for cross-chain peers (Hub and Spoke).
abstract contract OszillorPeer is
    IOszillorPeer,
    CCIPReceiver,
    PausableWithAccessControl,
    OszillorFees,
    IERC677Receiver
{
    mapping(uint64 => address) internal _peers;
    mapping(uint8 => uint256) internal _gasLimits;

    IERC20 public immutable feeToken;

    modifier onlyAllowedPeer(uint64 chainSelector, address sender) {
        if (_peers[chainSelector] != sender || sender == address(0)) {
            revert OszillorErrors.ZeroAddress();
        }
        _;
    }

    constructor(
        address router,
        address _feeToken,
        address admin,
        address feeRecipient
    ) CCIPReceiver(router) PausableWithAccessControl(admin) {
        if (_feeToken == address(0)) revert OszillorErrors.ZeroAddress();
        feeToken = IERC20(_feeToken);
        _initFees(feeRecipient);

        _setRoleAdmin(Roles.CROSS_CHAIN_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.FEE_WITHDRAWER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.FEE_RATE_SETTER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.EMERGENCY_PAUSER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(Roles.EMERGENCY_UNPAUSER_ROLE, DEFAULT_ADMIN_ROLE);

        _grantRole(Roles.CROSS_CHAIN_ADMIN_ROLE, admin);
    }

    function registerPeer(uint64 chainSelector, address peerAddress)
        external
        override
        onlyRole(Roles.CROSS_CHAIN_ADMIN_ROLE)
    {
        if (peerAddress == address(0)) revert OszillorErrors.ZeroAddress();
        _peers[chainSelector] = peerAddress;
        emit PeerRegistered(chainSelector, peerAddress);
    }

    function removePeer(uint64 chainSelector)
        external
        override
        onlyRole(Roles.CROSS_CHAIN_ADMIN_ROLE)
    {
        delete _peers[chainSelector];
        emit PeerRemoved(chainSelector);
    }

    function setGasLimit(uint8 messageType, uint256 gasLimit)
        external
        override
        onlyRole(Roles.CROSS_CHAIN_ADMIN_ROLE)
    {
        _gasLimits[messageType] = gasLimit;
        emit GasLimitUpdated(messageType, gasLimit);
    }

    function getPeer(uint64 chainSelector) external view override returns (address) {
        return _peers[chainSelector];
    }

    function isPeerRegistered(uint64 chainSelector) external view override returns (bool) {
        return _peers[chainSelector] != address(0);
    }

    function getGasLimit(uint8 messageType) external view override returns (uint256) {
        return _gasLimits[messageType];
    }

    function withdrawFees(IERC20 asset) external onlyRole(Roles.FEE_WITHDRAWER_ROLE) {
        _withdrawFees(asset);
    }

    function setFeeRate(uint256 newRateBps, uint256 currentTotalAssets) external onlyRole(Roles.FEE_RATE_SETTER_ROLE) {
        _setFeeRate(newRateBps, currentTotalAssets);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(CCIPReceiver, PausableWithAccessControl)
        returns (bool)
    {
        return CCIPReceiver.supportsInterface(interfaceId) || PausableWithAccessControl.supportsInterface(interfaceId);
    }

    function onTokenTransfer(
        address sender,
        uint256 amount,
        bytes calldata data
    ) external virtual override {
        // Implement token transfer handling for paying fees (e.g. LINK transferAndCall)
        // Basic stub since CCIP typically accepts native or specific ERC20 tokens
    }
}
