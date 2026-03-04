// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";

/// @title OszillorFees
/// @author Hitesh (vyqno)
/// @notice Abstract streaming management fee module for the OSZILLOR protocol.
/// @dev Fee = 0.5% annual (50 bps), accrues continuously. Collected on every
///      deposit/withdraw via `_collectFeeIfDue()`. NOT collected on rebase (MED-06 fix).
///      `accruedFees` accumulator tracks fees separately from vault balance.
///      `withdrawFees()` ONLY transfers `accruedFees`, NEVER `balanceOf(address(this))` (HIGH-07 fix).
///      Maximum fee cap: 200 bps (2% annual).
abstract contract OszillorFees {
    using SafeERC20 for IERC20;

    // ──────────────────── Events ────────────────────

    /// @notice Emitted when streaming fees are collected into the accumulator.
    /// @param amount Fee amount collected (in asset terms).
    /// @param timestamp Block timestamp of collection.
    event FeeCollected(uint256 amount, uint256 timestamp);

    /// @notice Emitted when accrued fees are withdrawn to the treasury.
    /// @param recipient Treasury address receiving the fees.
    /// @param amount Amount of fees withdrawn.
    event FeeWithdrawn(address indexed recipient, uint256 amount);

    /// @notice Emitted when the fee rate is updated.
    /// @param oldRateBps Previous fee rate in basis points.
    /// @param newRateBps New fee rate in basis points.
    event FeeRateUpdated(uint256 oldRateBps, uint256 newRateBps);

    // ──────────────────── Constants ────────────────────

    /// @notice Maximum allowed fee rate (2% annual).
    uint256 public constant MAX_FEE_BPS = 200;

    /// @notice Seconds in a year (365.25 days).
    uint256 internal constant SECONDS_PER_YEAR = 365.25 days;

    // ──────────────────── State ────────────────────

    /// @notice Current management fee rate in basis points (default: 50 = 0.5% annual).
    uint256 public feeRateBps;

    /// @notice Accumulated fees available for withdrawal to treasury.
    /// @dev CRITICAL: withdrawFees() must ONLY transfer this amount.
    uint256 public accruedFees;

    /// @notice Timestamp of the last fee collection.
    uint256 public lastFeeCollection;

    /// @notice Address receiving withdrawn fees.
    address public feeRecipient;

    // ──────────────────── Initialization ────────────────────

    /// @notice Initializes the fee module. Called once from the inheriting contract's constructor.
    /// @param recipient Address that will receive withdrawn fees (treasury multisig).
    function _initFees(address recipient) internal {
        if (recipient == address(0)) revert OszillorErrors.ZeroAddress();
        feeRateBps = 50; // 0.5% annual default
        feeRecipient = recipient;
        lastFeeCollection = block.timestamp;
    }

    // ──────────────────── Internal ────────────────────

    /// @notice Calculates the fee that has accrued since the last collection.
    /// @dev Fee = totalAssets * feeRateBps / 10000 * elapsed / SECONDS_PER_YEAR.
    ///      Time-weighted to prevent MEV sandwich attacks around rebases.
    /// @param currentTotalAssets The current total assets in the vault (internal accounting).
    /// @return fee The accrued fee amount in asset terms.
    function _calculateAccruedFee(uint256 currentTotalAssets) internal view returns (uint256 fee) {
        uint256 elapsed = block.timestamp - lastFeeCollection;
        if (elapsed == 0 || currentTotalAssets == 0) return 0;

        // annualFee = totalAssets * feeRateBps / 10000
        // periodFee = annualFee * elapsed / SECONDS_PER_YEAR
        fee = (currentTotalAssets * feeRateBps * elapsed) / (10_000 * SECONDS_PER_YEAR);
    }

    /// @notice Collects accrued fees into the accumulator. Called on deposit/withdraw.
    /// @dev NOT called on rebase — prevents MEV sandwich (MED-06 fix).
    ///      Fees are tracked via `accruedFees`, NOT transferred immediately.
    /// @param currentTotalAssets The current total assets in the vault.
    function _collectFeeIfDue(uint256 currentTotalAssets) internal {
        uint256 fee = _calculateAccruedFee(currentTotalAssets);
        if (fee > 0) {
            accruedFees += fee;
            emit FeeCollected(fee, block.timestamp);
        }
        lastFeeCollection = block.timestamp;
    }

    // ──────────────────── External ────────────────────

    /// @notice Withdraws all accrued fees to the fee recipient (treasury).
    /// @dev Callable only by FEE_WITHDRAWER_ROLE. CRITICAL: Only transfers `accruedFees`,
    ///      never `balanceOf(address(this))` — that would drain user deposits (HIGH-07 fix).
    /// @param asset The ERC-20 asset token to transfer fees in.
    function _withdrawFees(IERC20 asset) internal {
        uint256 amount = accruedFees;
        if (amount == 0) revert OszillorErrors.ZeroAmount();
        accruedFees = 0;
        asset.safeTransfer(feeRecipient, amount);
        emit FeeWithdrawn(feeRecipient, amount);
    }

    /// @notice Updates the management fee rate.
    /// @dev Callable only by FEE_RATE_SETTER_ROLE. Capped at MAX_FEE_BPS.
    /// @param newRateBps New fee rate in basis points.
    /// @param currentTotalAssets Current total assets (to collect pending fees first).
    function _setFeeRate(uint256 newRateBps, uint256 currentTotalAssets) internal {
        if (newRateBps > MAX_FEE_BPS) {
            revert OszillorErrors.FeeTooHigh(newRateBps, MAX_FEE_BPS);
        }
        // Collect pending fees at old rate before changing
        _collectFeeIfDue(currentTotalAssets);
        uint256 oldRate = feeRateBps;
        feeRateBps = newRateBps;
        emit FeeRateUpdated(oldRate, newRateBps);
    }
}
