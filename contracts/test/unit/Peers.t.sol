// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {HubPeer} from "../../src/peers/HubPeer.sol";
import {SpokePeer} from "../../src/peers/SpokePeer.sol";
import {IOszillorVault} from "../../src/interfaces/IOszillorVault.sol";
import {IOszillorToken} from "../../src/interfaces/IOszillorToken.sol";
import {Roles} from "../../src/libraries/Roles.sol";
import {MockRouter} from "../mocks/MockRouter.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {CcipMessageType, RiskStateSync, RiskLevel} from "../../src/libraries/DataStructures.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {OszillorErrors} from "../../src/libraries/OszillorErrors.sol";

// Mock Vault & Token for HubPeer testing
contract MockVaultForPeer {
    uint256 public currentRiskScore = 50;
    bool public emergencyMode = false;
}

contract MockTokenForPeer {
    uint256 public rebaseIndex = 1e18;
}

contract PeersTest is Test {
    HubPeer hub;
    SpokePeer spoke;
    MockRouter router;
    MockERC20 feeToken;
    MockVaultForPeer mockVault;
    MockTokenForPeer mockToken;

    address admin = makeAddr("admin");
    address treasury = makeAddr("treasury");
    address alien = makeAddr("alien");

    uint64 constant HUB_CHAIN = 1;
    uint64 constant SPOKE_CHAIN = 2;

    function setUp() public {
        vm.warp(1_700_000_000);

        router = new MockRouter();
        feeToken = new MockERC20();
        mockVault = new MockVaultForPeer();
        mockToken = new MockTokenForPeer();

        vm.startPrank(admin);

        hub = new HubPeer(
            address(router),
            address(feeToken),
            admin,
            treasury,
            address(mockVault),
            address(mockToken)
        );

        spoke = new SpokePeer(
            address(router),
            address(feeToken),
            admin,
            treasury,
            HUB_CHAIN
        );

        // Register peers globally
        hub.registerSpoke(SPOKE_CHAIN, address(spoke));
        spoke.registerPeer(HUB_CHAIN, address(hub));

        // Configure limits
        hub.setGasLimit(uint8(CcipMessageType.RISK_STATE_SYNC), 300_000);

        vm.stopPrank();
    }

    // ═════════════════════════════════════════════════════════════
    //                           HUB PEER
    // ═════════════════════════════════════════════════════════════

    function test_hub_registerSpoke() public {
        assertEq(hub.getPeer(SPOKE_CHAIN), address(spoke));
        
        uint64[] memory spokes = hub.getRegisteredSpokes();
        assertEq(spokes.length, 1);
        assertEq(spokes[0], SPOKE_CHAIN);
    }

    function test_hub_broadcastRiskState() public {
        vm.deal(admin, 1 ether);

        uint256 expectedNonce = hub.currentNonce() + 1;

        vm.expectEmit(true, true, true, true, address(hub));
        emit IHubPeer.RiskStateBroadcast(expectedNonce, 50, 1e18, false, 1);

        vm.prank(admin);
        hub.broadcastRiskState{value: 0.1 ether}();
        assertEq(hub.currentNonce(), expectedNonce);
    }

    // ═════════════════════════════════════════════════════════════
    //                          SPOKE PEER
    // ═════════════════════════════════════════════════════════════
    
    function test_spoke_staleness() public {
        assertTrue(spoke.isStateStale()); // Initial state is stale (lastHubUpdate = 0)
    }

    function test_spoke_receiveRiskStateSync() public {
        RiskStateSync memory stateSync = RiskStateSync({
            riskScore: 75, // DANGER
            rebaseIndex: 1.01e18,
            emergencyMode: false,
            timestamp: block.timestamp,
            nonce: 1
        });

        bytes memory messageData = abi.encode(CcipMessageType.RISK_STATE_SYNC, stateSync);
        
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: HUB_CHAIN,
            sender: abi.encode(address(hub)),
            data: messageData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        spoke.ccipReceive(message);

        assertEq(spoke.lastProcessedNonce(), 1);
        assertEq(spoke.lastReceivedRebaseIndex(), 1.01e18);
        assertEq(spoke.lastHubUpdate(), block.timestamp);
        assertEq(uint(spoke.spokeRiskLevel()), uint(RiskLevel.DANGER));
        assertFalse(spoke.isStateStale());
    }

    function test_spoke_receive_ReplayDetected() public {
        // Send nonce 1
        RiskStateSync memory stateSync = RiskStateSync({
            riskScore: 75,
            rebaseIndex: 1.01e18,
            emergencyMode: false,
            timestamp: block.timestamp,
            nonce: 1
        });

        bytes memory messageData = abi.encode(CcipMessageType.RISK_STATE_SYNC, stateSync);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: HUB_CHAIN,
            sender: abi.encode(address(hub)),
            data: messageData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        spoke.ccipReceive(message);

        // Try replay nonce 1
        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(OszillorErrors.ReplayDetected.selector, 1, 1));
        spoke.ccipReceive(message);
    }

    function test_spoke_receive_MessageTooOld() public {
        // Construct a message older than 5 minutes
        RiskStateSync memory stateSync = RiskStateSync({
            riskScore: 75,
            rebaseIndex: 1.01e18,
            emergencyMode: false,
            timestamp: block.timestamp - 6 minutes, // Too old!
            nonce: 1
        });

        bytes memory messageData = abi.encode(CcipMessageType.RISK_STATE_SYNC, stateSync);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: HUB_CHAIN,
            sender: abi.encode(address(hub)),
            data: messageData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(OszillorErrors.MessageTooOld.selector, block.timestamp - 6 minutes, 5 minutes));
        spoke.ccipReceive(message);
    }

    function test_spoke_receive_UnknownMessageType() public {
        bytes memory messageData = abi.encode(CcipMessageType.REBALANCE, "invalid_data");
        
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: HUB_CHAIN,
            sender: abi.encode(address(hub)),
            data: messageData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(abi.encodeWithSelector(OszillorErrors.UnknownMessageType.selector, uint8(CcipMessageType.REBALANCE)));
        spoke.ccipReceive(message);
    }

    function test_spoke_receive_OnlyAllowedPeer() public {
        RiskStateSync memory stateSync = RiskStateSync({
            riskScore: 75,
            rebaseIndex: 1.01e18,
            emergencyMode: false,
            timestamp: block.timestamp,
            nonce: 1
        });

        bytes memory messageData = abi.encode(CcipMessageType.RISK_STATE_SYNC, stateSync);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: HUB_CHAIN,
            sender: abi.encode(alien), // Not the registered Hub!
            data: messageData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        vm.expectRevert(OszillorErrors.ZeroAddress.selector); // NotAllowedPeer reverts with ZeroAddress
        spoke.ccipReceive(message);
    }

    // ═════════════════════════════════════════════════════════════
    //                   ENFORCEMENT (CRIT-04 + MED-01)
    // ═════════════════════════════════════════════════════════════

    function test_spoke_checkDepositAllowed_reverts_when_stale() public {
        // lastHubUpdate = 0, so spoke is already stale
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.RiskStateTooStale.selector,
                block.timestamp, // age = block.timestamp - 0
                15 minutes       // maxSpokeStaleness
            )
        );
        spoke.checkDepositAllowed();
    }

    function test_spoke_checkDepositAllowed_passes_when_fresh() public {
        // Sync a fresh state so spoke is not stale
        _syncSpoke(75, 1.01e18, false, 1);
        // Should NOT revert
        spoke.checkDepositAllowed();
    }

    function test_spoke_checkWithdrawalAllowed_reverts_on_divergence() public {
        // Sync with rebaseIndex = 1e18
        _syncSpoke(50, 1e18, false, 1);

        // Local index 6% higher → 600 bps divergence (> 500 bps threshold)
        vm.expectRevert(
            abi.encodeWithSelector(
                OszillorErrors.IndexDivergenceTooHigh.selector,
                600,  // divergenceBps
                500   // maxIndexDivergenceBps
            )
        );
        spoke.checkWithdrawalAllowed(1.06e18);
    }

    function test_spoke_checkWithdrawalAllowed_passes_within_bounds() public {
        // Sync with rebaseIndex = 1e18
        _syncSpoke(50, 1e18, false, 1);

        // Local index 4% higher → 400 bps (< 500 bps threshold) — should pass
        spoke.checkWithdrawalAllowed(1.04e18);
    }

    function test_spoke_checkDepositAllowed_reverts_in_emergency() public {
        // Sync state with emergency = true
        _syncSpoke(75, 1.01e18, true, 1);

        vm.expectRevert(OszillorErrors.EmergencyModeActive.selector);
        spoke.checkDepositAllowed();
    }

    // ═════════════════════════════════════════════════════════════
    //                          HELPERS
    // ═════════════════════════════════════════════════════════════

    function _syncSpoke(uint256 riskScore, uint256 rebaseIndex, bool emergency, uint256 nonce) internal {
        RiskStateSync memory stateSync = RiskStateSync({
            riskScore: riskScore,
            rebaseIndex: rebaseIndex,
            emergencyMode: emergency,
            timestamp: block.timestamp,
            nonce: nonce
        });

        bytes memory messageData = abi.encode(CcipMessageType.RISK_STATE_SYNC, stateSync);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(0),
            sourceChainSelector: HUB_CHAIN,
            sender: abi.encode(address(hub)),
            data: messageData,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        spoke.ccipReceive(message);
    }

    // Actors
    address alice = makeAddr("alice");
}

interface IHubPeer {
    event RiskStateBroadcast(
        uint256 indexed nonce,
        uint256 riskScore,
        uint256 rebaseIndex,
        bool emergencyMode,
        uint256 spokeCount
    );
}
