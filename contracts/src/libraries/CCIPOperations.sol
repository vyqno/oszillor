// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Client, IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CcipMessageType} from "./DataStructures.sol";

/// @title CCIPOperations
/// @author Hitesh (vyqno)
/// @notice CCIP message construction, fee handling, and token preparation helpers.
/// @dev Follows the YieldCoin production pattern for hub-spoke CCIP communication.
///      HIGH-09 fix: `allowOutOfOrderExecution` is set to `false` for state-dependent
///      messages (deposits, withdrawals, rebalances) to prevent ordering issues.
///      Risk state sync messages use `true` since they carry full state snapshots.
library CCIPOperations {
    using SafeERC20 for IERC20;

    // ──────────────────── Errors ────────────────────

    /// @notice The contract does not hold enough LINK to pay CCIP fees.
    /// @param linkBalance Current LINK balance of the contract.
    /// @param fees Required LINK fee for this message.
    error InsufficientLinkForFees(uint256 linkBalance, uint256 fees);

    /// @notice A token in the CCIP message does not match the expected address.
    /// @param invalidToken The unexpected token address.
    error InvalidToken(address invalidToken);

    /// @notice A token amount in the CCIP message does not match the expected value.
    /// @param invalidAmount The unexpected amount.
    error InvalidTokenAmount(uint256 invalidAmount);

    // ──────────────────── Message Building ────────────────────

    /// @notice Builds a CCIP EVM2Any message for hub-spoke communication.
    /// @param receiver Destination contract address (abi-encoded).
    /// @param messageType The OSZILLOR message type for routing on the receiver side.
    /// @param data ABI-encoded payload specific to the message type.
    /// @param tokenAmounts Token amounts to bridge alongside the message (can be empty).
    /// @param gasLimit Execution gas limit on the destination chain.
    /// @param link LINK token address used for fee payment.
    /// @param allowOutOfOrder Whether CCIP may execute this message out of order.
    /// @return evm2AnyMessage The constructed CCIP message struct.
    function buildMessage(
        address receiver,
        CcipMessageType messageType,
        bytes memory data,
        Client.EVMTokenAmount[] memory tokenAmounts,
        uint256 gasLimit,
        address link,
        bool allowOutOfOrder
    ) internal pure returns (Client.EVM2AnyMessage memory evm2AnyMessage) {
        evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(messageType, data),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: gasLimit,
                    allowOutOfOrderExecution: allowOutOfOrder
                })
            ),
            feeToken: link
        });
    }

    /// @notice Builds a state-dependent message (deposits, withdrawals, rebalances).
    /// @dev Wraps buildMessage with `allowOutOfOrderExecution = false` (HIGH-09 fix).
    function buildOrderedMessage(
        address receiver,
        CcipMessageType messageType,
        bytes memory data,
        Client.EVMTokenAmount[] memory tokenAmounts,
        uint256 gasLimit,
        address link
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        return buildMessage(receiver, messageType, data, tokenAmounts, gasLimit, link, false);
    }

    /// @notice Builds a risk state sync message (full state snapshot, order-independent).
    /// @dev Uses `allowOutOfOrderExecution = true` since each message carries
    ///      complete state — the spoke only needs the latest one.
    function buildSyncMessage(
        address receiver,
        bytes memory data,
        uint256 gasLimit,
        address link
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[] memory noTokens = new Client.EVMTokenAmount[](0);
        return buildMessage(
            receiver,
            CcipMessageType.RISK_STATE_SYNC,
            data,
            noTokens,
            gasLimit,
            link,
            true
        );
    }

    // ──────────────────── Fee Handling ────────────────────

    /// @notice Approves the CCIP router to spend LINK for message fees.
    /// @dev Reverts if the contract does not hold enough LINK.
    /// @param ccipRouter Address of the CCIP router.
    /// @param link LINK token address.
    /// @param dstChainSelector CCIP chain selector for the destination.
    /// @param evm2AnyMessage The CCIP message to estimate fees for.
    /// @return fees The LINK fee amount approved to the router.
    function handleFees(
        address ccipRouter,
        address link,
        uint64 dstChainSelector,
        Client.EVM2AnyMessage memory evm2AnyMessage
    ) internal returns (uint256 fees) {
        fees = IRouterClient(ccipRouter).getFee(dstChainSelector, evm2AnyMessage);
        uint256 linkBalance = LinkTokenInterface(link).balanceOf(address(this));
        if (fees > linkBalance) revert InsufficientLinkForFees(linkBalance, fees);
        IERC20(link).safeIncreaseAllowance(ccipRouter, fees);
    }

    // ──────────────────── Token Preparation ────────────────────

    /// @notice Prepares token amounts for a CCIP message that bridges an ERC-20.
    /// @param token The token to bridge.
    /// @param amount The amount to bridge (0 = no tokens).
    /// @param ccipRouter Address of the CCIP router (will receive approval).
    /// @return tokenAmounts Array for the CCIP message (length 0 or 1).
    function prepareTokenAmounts(IERC20 token, uint256 amount, address ccipRouter)
        internal
        returns (Client.EVMTokenAmount[] memory tokenAmounts)
    {
        if (amount > 0) {
            tokenAmounts = new Client.EVMTokenAmount[](1);
            tokenAmounts[0] = Client.EVMTokenAmount({token: address(token), amount: amount});
            token.safeIncreaseAllowance(ccipRouter, amount);
        } else {
            tokenAmounts = new Client.EVMTokenAmount[](0);
        }
    }

    // ──────────────────── Validation ────────────────────

    /// @notice Validates that received token amounts match expectations.
    /// @param tokenAmounts The token amounts from the received CCIP message.
    /// @param expectedToken The expected token address.
    /// @param expectedAmount The expected token amount.
    function validateTokenAmounts(
        Client.EVMTokenAmount[] memory tokenAmounts,
        address expectedToken,
        uint256 expectedAmount
    ) internal pure {
        if (tokenAmounts[0].token != expectedToken) {
            revert InvalidToken(tokenAmounts[0].token);
        }
        if (tokenAmounts[0].amount != expectedAmount) {
            revert InvalidTokenAmount(tokenAmounts[0].amount);
        }
    }
}
