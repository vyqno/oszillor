// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title OszillorErrors
/// @author Hitesh (vyqno)
/// @notice Custom errors for the OSZILLOR protocol.
/// @dev Grouped by domain. Never use string reverts — custom errors save gas
///      and provide structured revert data for off-chain decoding.
library OszillorErrors {
    // ──────────────────── Vault ────────────────────

    /// @notice The vault is in emergency mode; deposits are blocked.
    error EmergencyModeActive();

    /// @notice A zero amount was provided where a nonzero value is required.
    error ZeroAmount();

    /// @notice A zero address was provided where a valid address is required.
    error ZeroAddress();

    /// @notice The deposit amount is below the minimum threshold.
    /// @param provided The deposit amount attempted.
    /// @param minimum The minimum allowed deposit.
    error DepositTooSmall(uint256 provided, uint256 minimum);

    /// @notice The withdrawal exceeds the caller's available balance.
    /// @param requested Shares requested for withdrawal.
    /// @param available Shares the caller actually holds.
    error WithdrawalExceedsBalance(uint256 requested, uint256 available);

    /// @notice The requested emergency duration exceeds the protocol maximum.
    /// @param provided Duration requested in seconds.
    /// @param maximum Maximum allowed duration in seconds.
    error DurationTooLong(uint256 provided, uint256 maximum);

    /// @notice Allocation percentages do not sum to 10000 bps (100%).
    /// @param totalBps The actual sum of all allocation basis points.
    error InvalidAllocation(uint256 totalBps);

    /// @notice The proposed fee rate exceeds the protocol cap.
    /// @param provided Fee rate in basis points.
    /// @param maximum Maximum allowed fee rate in basis points.
    error FeeTooHigh(uint256 provided, uint256 maximum);

    // ──────────────────── Token ────────────────────

    /// @notice The sender does not hold enough shares for this operation.
    /// @param requested Shares required.
    /// @param available Shares the sender holds.
    error InsufficientShares(uint256 requested, uint256 available);

    /// @notice The spender's share allowance is insufficient for this transfer.
    /// @param requested Shares required.
    /// @param available Current share allowance.
    error InsufficientShareAllowance(uint256 requested, uint256 available);

    /// @notice The rebase factor is outside the allowed safety bounds.
    /// @param factor The factor that was provided.
    /// @param min Minimum allowed factor.
    /// @param max Maximum allowed factor.
    error RebaseFactorOutOfBounds(uint256 factor, uint256 min, uint256 max);

    // ──────────────────── CRE Receivers ────────────────────

    /// @notice The CRE report was not sent from the authorized forwarder.
    /// @param sender The actual msg.sender.
    /// @param expected The expected forwarder address.
    error NotForwarder(address sender, address expected);

    /// @notice The CRE report's workflow ID does not match the expected one.
    /// @param received The workflow ID from the report.
    /// @param expected The workflow ID configured at deployment.
    error WrongWorkflow(bytes32 received, bytes32 expected);

    /// @notice The CRE report's workflow owner does not match.
    /// @param received The owner address from the report.
    /// @param expected The expected owner address.
    error WrongOwner(address received, address expected);

    /// @notice The CRE report's workflow name does not match.
    /// @param received The name from the report.
    /// @param expected The expected workflow name.
    error WrongName(bytes32 received, bytes32 expected);

    /// @notice The risk score delta between consecutive updates exceeds the clamp limit.
    /// @param delta Absolute difference between old and new score.
    /// @param max Maximum allowed delta per update.
    error ScoreJumpTooLarge(uint256 delta, uint256 max);

    /// @notice The CRE DON consensus confidence is below the acceptance threshold.
    /// @param confidence The reported confidence value.
    /// @param minimum The minimum required confidence.
    error ConfidenceTooLow(uint256 confidence, uint256 minimum);

    /// @notice The risk update was submitted too soon after the previous one.
    /// @param nextAllowed Earliest timestamp for the next accepted update.
    error UpdateTooFrequent(uint256 nextAllowed);

    // ──────────────────── Cross-Chain ────────────────────

    /// @notice A CCIP message with a stale or duplicate nonce was received.
    /// @param nonce The nonce from the incoming message.
    /// @param lastNonce The last processed nonce on this spoke.
    error ReplayDetected(uint256 nonce, uint256 lastNonce);

    /// @notice A CCIP message timestamp is too old relative to the current block.
    /// @param timestamp The message's timestamp.
    /// @param maxAge Maximum age in seconds before a message is considered stale.
    error MessageTooOld(uint256 timestamp, uint256 maxAge);

    /// @notice The hub's risk state has not been updated within the allowed window.
    /// @param age Seconds since the last risk state update.
    /// @param maxAge Maximum allowed staleness in seconds.
    error RiskStateTooStale(uint256 age, uint256 maxAge);

    /// @notice The spoke's rebaseIndex has diverged too far from the hub's last broadcast.
    /// @param divergenceBps Actual divergence in basis points.
    /// @param maxBps Maximum allowed divergence in basis points.
    error IndexDivergenceTooHigh(uint256 divergenceBps, uint256 maxBps);

    /// @notice An unrecognized CCIP message type was received.
    /// @param messageType The unknown message type identifier.
    error UnknownMessageType(uint8 messageType);

    // ──────────────────── System State ────────────────────

    /// @notice The system is paused; CRE reports cannot be processed.
    error SystemPaused();

    // ──────────────────── Strategy ────────────────────

    /// @notice A Uniswap swap exceeded the maximum allowed slippage.
    /// @param expectedOut Expected output amount from Chainlink price.
    /// @param actualOut Actual output amount received.
    error SlippageTooHigh(uint256 expectedOut, uint256 actualOut);

    /// @notice The target ETH allocation is invalid (must be 0-10000 bps).
    /// @param targetBps The invalid target provided.
    error InvalidTargetAllocation(uint256 targetBps);

    /// @notice The strategy contract is paused and cannot execute rebalances.
    error StrategyPaused();

    /// @notice The Chainlink price feed returned a stale or invalid answer.
    /// @param updatedAt Timestamp of the last feed update.
    /// @param maxAge Maximum allowed staleness in seconds.
    error StalePriceFeed(uint256 updatedAt, uint256 maxAge);

    // ──────────────────── Donation Attack ────────────────────

    /// @notice Direct token transfer to the vault detected outside deposit flow.
    /// @param externalBalance The vault's actual token balance.
    /// @param internalAccounting The internally tracked total assets.
    error DonationDetected(uint256 externalBalance, uint256 internalAccounting);
}
