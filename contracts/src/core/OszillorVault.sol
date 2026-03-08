// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {PausableWithAccessControl} from "../modules/PausableWithAccessControl.sol";
import {OszillorFees} from "../modules/OszillorFees.sol";
import {IOszillorVault} from "../interfaces/IOszillorVault.sol";
import {IOszillorToken} from "../interfaces/IOszillorToken.sol";
import {IVaultStrategy} from "../interfaces/IVaultStrategy.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {ShareMath} from "../libraries/ShareMath.sol";
import {RiskMath} from "../libraries/RiskMath.sol";
import {Roles} from "../libraries/Roles.sol";
import {RiskLevel, RiskState, Allocation} from "../libraries/DataStructures.sol";

/// @title OszillorVault
/// @author Hitesh (vyqno)
/// @notice ERC-4626 compatible stablecoin vault for the OSZILLOR protocol.
/// @dev Central state hub — risk score, allocations, emergency mode, and fee streaming.
///      CRE receiver modules call into this contract via typed interface:
///        - RiskEngine   → updateRiskScore(), updateAllocations()
///        - RebaseExecutor → triggerRebase()
///        - EventSentinel → emergencyDeRisk()
///
///      Security fixes implemented:
///        CRIT-03 — Risk state initialized to CAUTION (score=50), not SAFE
///        CRIT-06 — Donation protection via `_internalTotalAssets` (never raw balanceOf)
///        HIGH-04 — All roles set in constructor; no post-deploy setController()
///        HIGH-06 — Emergency auto-expiry (max 4h) + manual UNPAUSER early exit
///        HIGH-11 — Risk staleness check (24h) blocks deposits when stale
///        MED-04  — Minimum deposit (1 USDC = 1e6)
///        MED-09  — Risk-aware maxDeposit/maxWithdraw
contract OszillorVault is
    PausableWithAccessControl,
    OszillorFees,
    ReentrancyGuard,
    IOszillorVault
{
    using SafeERC20 for IERC20;

    // ──────────────────── Constants ────────────────────

    /// @notice Minimum deposit amount — 0.001 ETH (MED-04 fix, updated for v2 WETH).
    uint256 public constant MIN_DEPOSIT = 1e15;

    /// @notice Maximum emergency duration — 4 hours (HIGH-06 fix).
    uint256 public constant MAX_EMERGENCY_DURATION = 4 hours;

    /// @notice Maximum risk data staleness before deposits are blocked (HIGH-11 fix).
    uint256 public constant MAX_RISK_STALENESS = 24 hours;

    // ──────────────────── Immutable ────────────────────

    /// @notice The base asset accepted by the vault (WETH for v2).
    IERC20 public immutable asset;

    /// @notice The OSZILLOR rebase token.
    IOszillorToken public immutable token;

    /// @notice The vault strategy contract (Lido staking + Uniswap hedging).
    IVaultStrategy public immutable strategy;

    // ──────────────────── State ────────────────────

    /// @notice Internally tracked total assets — NEVER raw balanceOf (CRIT-06 fix).
    uint256 private _internalTotalAssets;

    /// @notice Current on-chain risk state, updated by RiskEngine.
    RiskState private _riskState;

    /// @notice Current yield-source allocations.
    Allocation[] private _allocations;

    /// @notice Whether emergency mode is active.
    bool private _emergencyMode;

    /// @notice Timestamp when emergency mode auto-expires (HIGH-06 fix).
    uint256 private _emergencyModeExpiry;

    // ──────────────────── Constructor ────────────────────

    /// @notice Deploys the OSZILLOR vault with all roles set at construction time.
    /// @dev HIGH-04 fix: no post-deploy setController(). CRIT-03: risk init to CAUTION.
    /// @param _asset WETH address (v2 base asset).
    /// @param _token OszillorToken address.
    /// @param _riskEngine RiskEngine address (gets RISK_MANAGER_ROLE).
    /// @param _rebaseExecutor RebaseExecutor address (gets REBASE_EXECUTOR_ROLE).
    /// @param _sentinel EventSentinel address (gets SENTINEL_ROLE).
    /// @param _strategy VaultStrategy address (Lido + Uniswap integration).
    /// @param _admin Admin multisig address (5-day transfer delay).
    /// @param _feeRecipient Treasury address for fee withdrawal.
    constructor(
        address _asset,
        address _token,
        address _riskEngine,
        address _rebaseExecutor,
        address _sentinel,
        address _strategy,
        address _admin,
        address _feeRecipient
    ) PausableWithAccessControl(_admin) {
        asset = IERC20(_asset);
        token = IOszillorToken(_token);
        strategy = IVaultStrategy(_strategy);

        // HIGH-04: All roles set in constructor — no post-deploy setter
        _grantRole(Roles.RISK_MANAGER_ROLE, _riskEngine);
        // HIGH-NEW-01 fix: Vault no longer grants itself RISK_MANAGER_ROLE.
        // Token mint/burn uses TOKEN_MINTER_ROLE instead (granted on OszillorToken).
        _grantRole(Roles.REBASE_EXECUTOR_ROLE, _rebaseExecutor);
        _grantRole(Roles.SENTINEL_ROLE, _sentinel);

        // CRIT-03: Initialize risk to CAUTION (fail-closed), NOT SAFE
        _riskState = RiskState({
            riskScore: 50,
            confidence: 0,
            timestamp: block.timestamp,
            reasoningHash: bytes32(0)
        });

        // Initialize streaming fees
        _initFees(_feeRecipient);
    }

    // ══════════════════════════════════════════════════════════════
    //                     DEPOSIT / WITHDRAW
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IOszillorVault
    function deposit(uint256 assets) external nonReentrant returns (uint256 shares) {
        // Check emergency mode (auto-expiry check)
        _checkAndLiftEmergency();
        if (_emergencyMode) revert OszillorErrors.EmergencyModeActive();

        // MED-04: Minimum deposit
        if (assets < MIN_DEPOSIT) {
            revert OszillorErrors.DepositTooSmall(assets, MIN_DEPOSIT);
        }

        // HIGH-11: Risk staleness check
        _checkRiskStaleness();

        // Collect streaming fees before share calculation (MED-06)
        _collectFeeIfDue(_internalTotalAssets);

        // Calculate shares using vault-level accounting (CRIT-01 virtual offsets)
        shares = ShareMath.amountToShares(assets, token.totalShares(), _internalTotalAssets);
        if (shares == 0) revert OszillorErrors.ZeroAmount();

        // Effects — update internal accounting BEFORE external call (CEI)
        _internalTotalAssets += assets;

        // Mint shares to depositor via token
        token.mintShares(msg.sender, shares);

        // Interactions — pull WETH from depositor
        asset.safeTransferFrom(msg.sender, address(this), assets);

        // CRIT-NEW-02 fix: Send WETH to strategy for custody, but do NOT auto-stake.
        // The next W3 rebalance cycle will allocate per the current risk tier.
        // Auto-staking 100% to Lido violated the risk model during elevated risk states.
        asset.safeTransfer(address(strategy), assets);

        emit Deposit(msg.sender, assets, shares);
    }

    /// @inheritdoc IOszillorVault
    function withdraw(uint256 shares) external nonReentrant returns (uint256 assets) {
        // Withdrawals ALWAYS allowed — even during emergency (HIGH-06)
        if (shares == 0) revert OszillorErrors.ZeroAmount();

        // Check caller has enough shares
        uint256 callerShares = token.sharesOf(msg.sender);
        if (callerShares < shares) {
            revert OszillorErrors.WithdrawalExceedsBalance(shares, callerShares);
        }

        // Collect streaming fees before share calculation (MED-06)
        _collectFeeIfDue(_internalTotalAssets);

        // Calculate assets using vault-level accounting
        assets = ShareMath.sharesToAmount(shares, token.totalShares(), _internalTotalAssets);
        if (assets == 0) revert OszillorErrors.ZeroAmount();

        // Effects — update internal accounting BEFORE external call (CEI)
        _internalTotalAssets -= assets;

        // Burn shares from withdrawer
        token.burnShares(msg.sender, shares);

        // Ensure vault has enough liquidity (pull from strategy if needed)
        _ensureLiquidity(assets);

        // Interactions — push WETH to withdrawer
        asset.safeTransfer(msg.sender, assets);

        emit Withdraw(msg.sender, assets, shares);
    }

    // ══════════════════════════════════════════════════════════════
    //                     RISK MANAGEMENT (privileged)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IOszillorVault
    /// @dev HIGH-NEW-01 fix: Added bounds check [0, 100] to prevent invalid risk scores.
    function updateRiskScore(
        uint256 score,
        uint256 confidence,
        bytes32 reasoningHash
    ) external onlyRole(Roles.RISK_MANAGER_ROLE) {
        if (score > 100) revert OszillorErrors.InvalidRiskScore(score);

        _riskState = RiskState({
            riskScore: score,
            confidence: confidence,
            timestamp: block.timestamp,
            reasoningHash: reasoningHash
        });

        emit RiskScoreUpdated(score, confidence, reasoningHash);

        // MED-07: Emit warning when score enters CRITICAL zone
        if (score >= RiskMath.CRITICAL_THRESHOLD) {
            emit RiskScoreWarning(score, RiskMath.riskLevel(score));
        }
    }

    /// @inheritdoc IOszillorVault
    function updateAllocations(Allocation[] calldata allocs) external onlyRole(Roles.RISK_MANAGER_ROLE) {
        // Validate total allocation sums to 100%
        uint256 totalBps;
        for (uint256 i = 0; i < allocs.length; i++) {
            totalBps += allocs[i].percentageBps;
        }
        if (totalBps != 10_000) revert OszillorErrors.InvalidAllocation(totalBps);

        // Clear and repopulate
        delete _allocations;
        for (uint256 i = 0; i < allocs.length; i++) {
            _allocations.push(allocs[i]);
        }

        emit AllocationUpdated(allocs.length);
    }

    /// @inheritdoc IOszillorVault
    function triggerRebase(uint256 factor) external onlyRole(Roles.REBASE_EXECUTOR_ROLE) {
        uint256 newIndex = token.rebase(factor);
        emit RebaseTriggered(factor, newIndex);
    }

    /// @inheritdoc IOszillorVault
    function rebalance(uint256 targetEthPct) external onlyRole(Roles.REBASE_EXECUTOR_ROLE) {
        strategy.rebalance(targetEthPct);
        emit Rebalanced(targetEthPct, strategy.currentEthPct());
    }

    /// @inheritdoc IOszillorVault
    function totalNav() external view returns (uint256) {
        // NAV = WETH held by vault + strategy positions (WETH + stETH + USDC→ETH)
        uint256 vaultWeth = asset.balanceOf(address(this));
        uint256 strategyNav = strategy.totalValueInEth();
        return vaultWeth + strategyNav;
    }

    // ══════════════════════════════════════════════════════════════
    //                     EMERGENCY MODE (HIGH-06)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IOszillorVault
    function emergencyDeRisk(string calldata reason, uint256 duration) external onlyRole(Roles.SENTINEL_ROLE) {
        // Cap duration to MAX_EMERGENCY_DURATION
        if (duration > MAX_EMERGENCY_DURATION) {
            revert OszillorErrors.DurationTooLong(duration, MAX_EMERGENCY_DURATION);
        }
        if (duration == 0) duration = 1 hours; // Sensible default

        _emergencyMode = true;
        _emergencyModeExpiry = block.timestamp + duration;

        emit EmergencyDeRisk(reason, duration, _emergencyModeExpiry);
    }

    /// @inheritdoc IOszillorVault
    function exitEmergencyMode() external onlyRole(Roles.EMERGENCY_UNPAUSER_ROLE) {
        _emergencyMode = false;
        _emergencyModeExpiry = 0;

        emit EmergencyExited(msg.sender, block.timestamp);
    }

    // ══════════════════════════════════════════════════════════════
    //                     FEE MANAGEMENT
    // ══════════════════════════════════════════════════════════════

    /// @notice Withdraws all accrued streaming fees to the treasury.
    /// @dev Only FEE_WITHDRAWER_ROLE. HIGH-07: Only transfers accruedFees, never full balance.
    ///      CRIT-NEW-01 fix: Decrements _internalTotalAssets to prevent phantom asset deficit.
    function withdrawFees() external onlyRole(Roles.FEE_WITHDRAWER_ROLE) {
        uint256 amount = accruedFees;
        if (amount == 0) revert OszillorErrors.ZeroAmount();
        _internalTotalAssets -= amount;
        _ensureLiquidity(amount);
        _withdrawFees(asset);
    }

    /// @notice Updates the management fee rate.
    /// @dev Only FEE_RATE_SETTER_ROLE. Capped at MAX_FEE_BPS (200 bps = 2%).
    /// @param newRateBps New fee rate in basis points.
    function setFeeRate(uint256 newRateBps) external onlyRole(Roles.FEE_RATE_SETTER_ROLE) {
        _setFeeRate(newRateBps, _internalTotalAssets);
    }

    // ══════════════════════════════════════════════════════════════
    //                     VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IOszillorVault
    function currentRiskScore() external view returns (uint256) {
        return _riskState.riskScore;
    }

    /// @inheritdoc IOszillorVault
    function riskState() external view returns (RiskState memory) {
        return _riskState;
    }

    /// @inheritdoc IOszillorVault
    function totalAssets() external view returns (uint256) {
        // CRIT-06: Return internal accounting, NEVER raw balanceOf
        return _internalTotalAssets;
    }

    /// @inheritdoc IOszillorVault
    function internalTotalAssets() external view returns (uint256) {
        return _internalTotalAssets;
    }

    /// @inheritdoc IOszillorVault
    function emergencyMode() external view returns (bool) {
        // Check auto-expiry without modifying state (view-safe)
        if (_emergencyMode && block.timestamp >= _emergencyModeExpiry) {
            return false; // Expired but not yet lifted in storage
        }
        return _emergencyMode;
    }

    /// @inheritdoc IOszillorVault
    function riskLevel() external view returns (RiskLevel) {
        return RiskMath.riskLevel(_riskState.riskScore);
    }

    /// @inheritdoc IOszillorVault
    function getAllocations() external view returns (Allocation[] memory) {
        return _allocations;
    }

    /// @inheritdoc IOszillorVault
    /// @dev MED-09: Returns 0 if emergency mode or DANGER/CRITICAL risk tier.
    function maxDeposit(address) external view returns (uint256) {
        // Emergency mode check (including auto-expiry)
        if (_emergencyMode && block.timestamp < _emergencyModeExpiry) return 0;
        // DANGER or CRITICAL → deposits blocked
        if (_riskState.riskScore >= RiskMath.DANGER_THRESHOLD) return 0;
        return type(uint256).max;
    }

    /// @inheritdoc IOszillorVault
    function maxWithdraw(address owner) external view returns (uint256) {
        uint256 shares = token.sharesOf(owner);
        return ShareMath.sharesToAmount(shares, token.totalShares(), _internalTotalAssets);
    }

    // ══════════════════════════════════════════════════════════════
    //                     INTERNAL HELPERS
    // ══════════════════════════════════════════════════════════════

    /// @dev Pulls WETH from strategy if vault lacks liquidity to fulfill a transfer.
    ///      HIGH-NEW-03 fix: Checks return value and reverts with meaningful error.
    function _ensureLiquidity(uint256 needed) internal {
        uint256 vaultBalance = asset.balanceOf(address(this));
        if (vaultBalance < needed) {
            uint256 received = strategy.withdrawToVault(needed - vaultBalance);
            uint256 totalAvailable = vaultBalance + received;
            if (totalAvailable < needed) {
                revert OszillorErrors.InsufficientLiquidity(needed, totalAvailable);
            }
        }
    }

    /// @dev Checks if emergency mode has expired and lifts it if so (HIGH-06 auto-expiry).
    function _checkAndLiftEmergency() internal {
        if (_emergencyMode && block.timestamp >= _emergencyModeExpiry) {
            _emergencyMode = false;
            _emergencyModeExpiry = 0;
            emit EmergencyExpired(block.timestamp);
        }
    }

    /// @dev Blocks deposits if risk data is stale (HIGH-11 fix).
    function _checkRiskStaleness() internal view {
        uint256 age = block.timestamp - _riskState.timestamp;
        if (age > MAX_RISK_STALENESS) {
            revert OszillorErrors.RiskStateTooStale(age, MAX_RISK_STALENESS);
        }
    }

    // ══════════════════════════════════════════════════════════════
    //                     DIAMOND RESOLUTION
    // ══════════════════════════════════════════════════════════════

    /// @dev Required by Solidity for multiple-inheritance resolution.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(PausableWithAccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function grantRole(bytes32 role, address account)
        public
        override(PausableWithAccessControl)
    {
        super.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account)
        public
        override(PausableWithAccessControl)
    {
        super.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account)
        public
        override(PausableWithAccessControl)
    {
        super.renounceRole(role, account);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole)
        internal
        override(PausableWithAccessControl)
    {
        super._setRoleAdmin(role, adminRole);
    }

    function _grantRole(bytes32 role, address account)
        internal
        override(PausableWithAccessControl)
        returns (bool)
    {
        return super._grantRole(role, account);
    }

    function _revokeRole(bytes32 role, address account)
        internal
        override(PausableWithAccessControl)
        returns (bool)
    {
        return super._revokeRole(role, account);
    }
}
