// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {OszillorPeer} from "./OszillorPeer.sol";
import {IHubPeer} from "../interfaces/IHubPeer.sol";
import {IOszillorVault} from "../interfaces/IOszillorVault.sol";
import {IOszillorToken} from "../interfaces/IOszillorToken.sol";
import {CcipMessageType, RiskStateSync} from "../libraries/DataStructures.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {Roles} from "../libraries/Roles.sol";

/// @title HubPeer
/// @author Hitesh (vyqno)
/// @notice Hub-chain CCIP peer contract.
contract HubPeer is OszillorPeer, IHubPeer {
    uint256 public override currentNonce;
    IOszillorVault public immutable vault;
    IOszillorToken public immutable token;
    
    // Array to hold registered spoke chain selectors to broadcast
    uint64[] private _spokeChainSelectors;

    constructor(
        address router,
        address _feeToken,
        address admin,
        address feeRecipient,
        address _vault,
        address _token
    ) OszillorPeer(router, _feeToken, admin, feeRecipient) {
        if (_vault == address(0) || _token == address(0)) revert OszillorErrors.ZeroAddress();
        vault = IOszillorVault(_vault);
        token = IOszillorToken(_token);
    }

    function registerSpoke(uint64 chainSelector, address spokeAddress) external override onlyRole(Roles.CROSS_CHAIN_ADMIN_ROLE) {
        if (!_isRegistered(chainSelector)) {
            _spokeChainSelectors.push(chainSelector);
        }
        _peers[chainSelector] = spokeAddress;
        emit SpokeRegistered(chainSelector, spokeAddress);
        emit PeerRegistered(chainSelector, spokeAddress);
    }

    function _isRegistered(uint64 chainSelector) internal view returns (bool) {
        for (uint256 i = 0; i < _spokeChainSelectors.length; i++) {
            if (_spokeChainSelectors[i] == chainSelector) return true;
        }
        return false;
    }

    function getRegisteredSpokes() external view override returns (uint64[] memory) {
        return _spokeChainSelectors;
    }

    function broadcastRiskState() external payable override whenNotPaused {
        uint256 nonce = ++currentNonce;
        
        RiskStateSync memory stateSync = RiskStateSync({
            riskScore: vault.currentRiskScore(),
            rebaseIndex: token.rebaseIndex(),
            emergencyMode: vault.emergencyMode(),
            timestamp: block.timestamp,
            nonce: nonce
        });

        bytes memory messageData = abi.encode(CcipMessageType.RISK_STATE_SYNC, stateSync);

        uint256 count = _spokeChainSelectors.length;
        for (uint256 i = 0; i < count; i++) {
            uint64 chainSelector = _spokeChainSelectors[i];
            address spokeAddress = _peers[chainSelector];
            
            if (spokeAddress != address(0)) {
                Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
                    receiver: abi.encode(spokeAddress),
                    data: messageData,
                    tokenAmounts: new Client.EVMTokenAmount[](0),
                    extraArgs: Client._argsToBytes(
                        Client.EVMExtraArgsV2({
                            gasLimit: _gasLimits[uint8(CcipMessageType.RISK_STATE_SYNC)],
                            allowOutOfOrderExecution: false
                        })
                    ),
                    feeToken: address(0) // Assuming native payment for now
                });
                
                IRouterClient router = IRouterClient(this.getRouter());
                uint256 fee = router.getFee(chainSelector, message);
                
                // User pays the fee using msg.value if Native.
                // Could also use LINK if feeToken was provided.
                router.ccipSend{value: fee}(chainSelector, message);
            }
        }
        
        emit RiskStateBroadcast(
            nonce,
            stateSync.riskScore,
            stateSync.rebaseIndex,
            stateSync.emergencyMode,
            count
        );
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Implement receiving logic for cross-chain actions from spokes if any
    }
}
