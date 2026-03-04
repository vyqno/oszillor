// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IOszillorToken} from "../interfaces/IOszillorToken.sol";
import {IERC677Receiver} from "../interfaces/IERC677Receiver.sol";
import {ShareMath} from "../libraries/ShareMath.sol";
import {RiskMath} from "../libraries/RiskMath.sol";
import {Roles} from "../libraries/Roles.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";

/// @title OszillorToken
/// @author Hitesh (vyqno)
/// @notice Risk-reactive rebase ERC-20 + ERC-677 token for the OSZILLOR protocol.
/// @dev Share-based internal accounting: `balanceOf(addr) = shares[addr] * rebaseIndex / 1e18`.
///      A rebase changes ONE global variable (`_rebaseIndex`), instantly adjusting all
///      balances in O(1) — no per-user storage writes.
///
///      Security fixes implemented:
///        CRIT-02 — Factor bounds [0.99e18, 1.01e18] + index bounds [1e16, 1e20]
///        HIGH-01 — Allowances stored in shares, not amounts (rebase-safe)
///        HIGH-02 — `transferAndCall` is `nonReentrant`
///        MED-10  — `approveShares()` for power users wanting deterministic allowances
///
///      Inherits ERC20 for interface compatibility, but OVERRIDES all balance/transfer
///      logic to use internal shares. OZ's `_update()` is made empty.
contract OszillorToken is ERC20, AccessControlDefaultAdminRules, ReentrancyGuard, IOszillorToken {
    using Math for uint256;

    // ──────────────────── State ────────────────────

    /// @notice Internal share balances — the ONLY storage that matters for accounting.
    mapping(address => uint256) private _shares;

    /// @notice Share-based allowances (HIGH-01 fix). Immune to stale-allowance after rebase.
    mapping(address => mapping(address => uint256)) private _shareAllowances;

    /// @notice Total shares across all holders.
    uint256 private _totalShares;

    /// @notice Global rebase index (1e18 precision). Changed only by `rebase()`.
    uint256 private _rebaseIndex;

    /// @notice Monotonically increasing rebase epoch counter.
    uint256 private _epoch;

    /// @notice Timestamp of the last successful rebase.
    uint256 private _lastRebaseTimestamp;

    // ──────────────────── Constructor ────────────────────

    /// @notice Deploys the OSZILLOR rebase token.
    /// @param name_ Token name (e.g., "OSZILLOR").
    /// @param symbol_ Token symbol (e.g., "OSZ").
    /// @param admin Initial admin address (multisig, 5-day transfer delay).
    constructor(
        string memory name_,
        string memory symbol_,
        address admin
    )
        ERC20(name_, symbol_)
        AccessControlDefaultAdminRules(5 days, admin)
    {
        _rebaseIndex = RiskMath.PRECISION; // 1e18 — initial index
        _lastRebaseTimestamp = block.timestamp;
    }

    // ══════════════════════════════════════════════════════════════
    //                     ERC-20 OVERRIDES (share-based)
    // ══════════════════════════════════════════════════════════════

    /// @notice Returns the elastic (rebased) balance for an account.
    /// @dev Computed fresh on every call: shares * rebaseIndex / 1e18.
    function balanceOf(address account) public view override(ERC20) returns (uint256) {
        return ShareMath.sharesToAmountByIndex(_shares[account], _rebaseIndex);
    }

    /// @notice Returns the total elastic supply across all holders.
    function totalSupply() public view override(ERC20) returns (uint256) {
        return ShareMath.sharesToAmountByIndex(_totalShares, _rebaseIndex);
    }

    /// @notice Transfers rebased amount from caller to recipient.
    /// @dev Converts amount to shares, moves shares, emits Transfer (amounts) + TransferShares.
    function transfer(address to, uint256 amount) public override(ERC20) returns (bool) {
        _transferShares(msg.sender, to, _amountToShares(amount), amount);
        return true;
    }

    /// @notice Transfers rebased amount from `from` to `to` using share allowance.
    /// @dev Spends share allowance, converts amount to shares, moves shares.
    function transferFrom(address from, address to, uint256 amount) public override(ERC20) returns (bool) {
        uint256 sharesToTransfer = _amountToShares(amount);
        _spendShareAllowance(from, msg.sender, sharesToTransfer);
        _transferShares(from, to, sharesToTransfer, amount);
        return true;
    }

    /// @notice Approves spender for a rebased amount (stored internally as shares).
    /// @dev HIGH-01 fix: amount is converted to shares before storage, so allowance
    ///      adjusts automatically with rebases.
    function approve(address spender, uint256 amount) public override(ERC20) returns (bool) {
        uint256 shareAmount = _amountToShares(amount);
        _shareAllowances[msg.sender][spender] = shareAmount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Returns the current allowance in rebased (amount) terms.
    /// @dev Converts internal share allowance back to amount for ERC-20 compatibility.
    function allowance(address owner, address spender) public view override(ERC20) returns (uint256) {
        return ShareMath.sharesToAmountByIndex(_shareAllowances[owner][spender], _rebaseIndex);
    }

    /// @dev Empty — we manage shares directly, not via OZ's internal balance system.
    function _update(address, address, uint256) internal pure override {
        // Intentionally empty. All accounting is share-based.
    }

    // ══════════════════════════════════════════════════════════════
    //                     ERC-677: transferAndCall
    // ══════════════════════════════════════════════════════════════

    /// @notice Transfers tokens and calls `onTokenTransfer` on the recipient in one tx.
    /// @dev HIGH-02 fix: `nonReentrant` prevents reentrancy from callback.
    /// @param to Recipient address (must implement IERC677Receiver if contract).
    /// @param amount Rebased amount to transfer.
    /// @param data Arbitrary data forwarded to the callback.
    /// @return True on success.
    function transferAndCall(
        address to,
        uint256 amount,
        bytes calldata data
    ) external nonReentrant returns (bool) {
        transfer(to, amount);
        if (to.code.length > 0) {
            IERC677Receiver(to).onTokenTransfer(msg.sender, amount, data);
        }
        return true;
    }

    // ══════════════════════════════════════════════════════════════
    //                     SHARE MANAGEMENT (privileged)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IOszillorToken
    function mintShares(address to, uint256 shares) external onlyRole(Roles.RISK_MANAGER_ROLE) {
        if (to == address(0)) revert OszillorErrors.ZeroAddress();
        if (shares == 0) revert OszillorErrors.ZeroAmount();

        _totalShares += shares;
        _shares[to] += shares;

        uint256 amount = ShareMath.sharesToAmountByIndex(shares, _rebaseIndex);
        emit Transfer(address(0), to, amount);
        emit TransferShares(address(0), to, shares);
    }

    /// @inheritdoc IOszillorToken
    function burnShares(address from, uint256 shares) external onlyRole(Roles.RISK_MANAGER_ROLE) {
        if (from == address(0)) revert OszillorErrors.ZeroAddress();
        if (shares == 0) revert OszillorErrors.ZeroAmount();
        if (_shares[from] < shares) {
            revert OszillorErrors.InsufficientShares(shares, _shares[from]);
        }

        _shares[from] -= shares;
        _totalShares -= shares;

        uint256 amount = ShareMath.sharesToAmountByIndex(shares, _rebaseIndex);
        emit Transfer(from, address(0), amount);
        emit TransferShares(from, address(0), shares);
    }

    // ══════════════════════════════════════════════════════════════
    //                     REBASE (privileged)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IOszillorToken
    function rebase(uint256 factor) external onlyRole(Roles.REBASE_EXECUTOR_ROLE) returns (uint256 newIndex) {
        // CRIT-02: Factor bounds enforcement
        if (factor < RiskMath.MIN_REBASE_FACTOR || factor > RiskMath.MAX_REBASE_FACTOR) {
            revert OszillorErrors.RebaseFactorOutOfBounds(
                factor, RiskMath.MIN_REBASE_FACTOR, RiskMath.MAX_REBASE_FACTOR
            );
        }

        // Apply factor with index clamping (CRIT-02)
        newIndex = RiskMath.applyRebase(_rebaseIndex, factor);
        _rebaseIndex = newIndex;
        _lastRebaseTimestamp = block.timestamp;

        emit Rebase(++_epoch, newIndex);
    }

    // ══════════════════════════════════════════════════════════════
    //                     SHARE-BASED APPROVAL (MED-10)
    // ══════════════════════════════════════════════════════════════

    /// @notice Approves spender for an exact number of shares (deterministic, rebase-immune).
    /// @dev MED-10 fix: Power users can approve in share terms for predictable behavior.
    /// @param spender Address to approve.
    /// @param shareAmount Number of shares to approve.
    /// @return True on success.
    function approveShares(address spender, uint256 shareAmount) external returns (bool) {
        _shareAllowances[msg.sender][spender] = shareAmount;
        uint256 amount = ShareMath.sharesToAmountByIndex(shareAmount, _rebaseIndex);
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /// @notice Returns the raw share allowance (not converted to amount).
    /// @param owner Token owner.
    /// @param spender Approved spender.
    /// @return Share allowance.
    function shareAllowance(address owner, address spender) external view returns (uint256) {
        return _shareAllowances[owner][spender];
    }

    // ══════════════════════════════════════════════════════════════
    //                     VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IOszillorToken
    function sharesOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    /// @inheritdoc IOszillorToken
    function rebaseIndex() external view returns (uint256) {
        return _rebaseIndex;
    }

    /// @inheritdoc IOszillorToken
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    /// @inheritdoc IOszillorToken
    function lastRebaseTimestamp() external view returns (uint256) {
        return _lastRebaseTimestamp;
    }

    /// @notice Returns the current rebase epoch number.
    function epoch() external view returns (uint256) {
        return _epoch;
    }

    // ══════════════════════════════════════════════════════════════
    //                     DIAMOND RESOLUTION
    // ══════════════════════════════════════════════════════════════

    /// @dev Required by Solidity for multiple-inheritance resolution.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlDefaultAdminRules)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // ══════════════════════════════════════════════════════════════
    //                     INTERNAL HELPERS
    // ══════════════════════════════════════════════════════════════

    /// @dev Converts a rebased amount to internal shares at current index.
    function _amountToShares(uint256 amount) internal view returns (uint256) {
        return ShareMath.amountToSharesByIndex(amount, _rebaseIndex);
    }

    /// @dev Moves shares from `from` to `to`, emitting both Transfer and TransferShares.
    function _transferShares(address from, address to, uint256 shareAmount, uint256 amount) internal {
        if (from == address(0)) revert OszillorErrors.ZeroAddress();
        if (to == address(0)) revert OszillorErrors.ZeroAddress();
        if (_shares[from] < shareAmount) {
            revert OszillorErrors.InsufficientShares(shareAmount, _shares[from]);
        }

        _shares[from] -= shareAmount;
        _shares[to] += shareAmount;

        emit Transfer(from, to, amount);
        emit TransferShares(from, to, shareAmount);
    }

    /// @dev Spends share allowance, reverting if insufficient.
    function _spendShareAllowance(address owner, address spender, uint256 shareAmount) internal {
        uint256 currentAllowance = _shareAllowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < shareAmount) {
                revert OszillorErrors.InsufficientShareAllowance(shareAmount, currentAllowance);
            }
            unchecked {
                _shareAllowances[owner][spender] = currentAllowance - shareAmount;
            }
        }
    }
}
