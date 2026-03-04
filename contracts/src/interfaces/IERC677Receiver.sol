// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IERC677Receiver
/// @author Hitesh (vyqno)
/// @notice Callback interface for ERC-677 `transferAndCall` recipients.
/// @dev Contracts implementing this interface can react to token transfers in a single
///      transaction (no approve+transferFrom pattern needed). Used by OszillorVault for
///      single-tx withdrawals. The caller's `transferAndCall` MUST be `nonReentrant`
///      (HIGH-02 fix).
interface IERC677Receiver {
    /// @notice Called by the token contract after a successful `transferAndCall`.
    /// @param sender The original initiator of the transfer (NOT `msg.sender`).
    /// @param value Amount of tokens transferred.
    /// @param data Arbitrary data forwarded from the caller.
    function onTokenTransfer(address sender, uint256 value, bytes calldata data) external;
}
