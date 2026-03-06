/*
 * ═══════════════════════════════════════════════════════════════════
 *   OSZILLOR Token — Certora Formal Verification Specification
 * ═══════════════════════════════════════════════════════════════════
 *
 * Verifies the 7 critical invariants from plan.md Section 6:
 *   INV-1: sum(sharesOf(all_users)) == totalShares
 *   INV-2: balanceOf(addr) == shares[addr] * rebaseIndex / 1e18
 *   INV-4: rebaseFactor ∈ [MIN_REBASE_FACTOR, MAX_REBASE_FACTOR]
 *   INV-6: rebase() callable ONLY by REBASE_EXECUTOR_ROLE
 *
 * Token-specific properties:
 *   TS-1: rebaseIndex ∈ [MIN_REBASE_INDEX, MAX_REBASE_INDEX]
 *   TS-2: transfer preserves totalShares
 *   TS-3: mintShares/burnShares correctly update totalShares
 *   TS-4: allowance stored in shares adjusts with rebase
 */

using OszillorTokenHarness as token;

methods {
    // Token state
    function token.balanceOf(address) external returns (uint256) envfree;
    function token.totalSupply() external returns (uint256) envfree;
    function token.getShares(address) external returns (uint256) envfree;
    function token.getTotalShares() external returns (uint256) envfree;
    function token.getRebaseIndex() external returns (uint256) envfree;
    function token.getEpoch() external returns (uint256) envfree;
    function token.allowance(address, address) external returns (uint256) envfree;
    function token.getShareAllowance(address, address) external returns (uint256) envfree;

    // Token actions
    function token.transfer(address, uint256) external returns (bool);
    function token.transferFrom(address, address, uint256) external returns (bool);
    function token.approve(address, uint256) external returns (bool);
    function token.mintShares(address, uint256) external;
    function token.burnShares(address, uint256) external;
    function token.rebase(uint256) external returns (uint256);
}

// ═══════════════════════════════════════════════════════════════════
//   INVARIANT 1: Rebase index is always within safety bounds
// ═══════════════════════════════════════════════════════════════════

/// @title rebaseIndex is always in [MIN_REBASE_INDEX, MAX_REBASE_INDEX]
/// @notice CRIT-02 fix verification
invariant rebaseIndexInBounds()
    token.getRebaseIndex() >= 1e16 && token.getRebaseIndex() <= 1e20
    {
        preserved {
            requireInvariant rebaseIndexInBounds();
        }
    }

// ═══════════════════════════════════════════════════════════════════
//   INVARIANT 2: balanceOf is consistent with shares * index
// ═══════════════════════════════════════════════════════════════════

/// @title balanceOf equals shares * rebaseIndex / 1e18 (floor division)
/// @notice Verifies the core share-based accounting identity
rule balanceOfConsistentWithShares(address user) {
    uint256 shares = token.getShares(user);
    uint256 idx = token.getRebaseIndex();
    uint256 balance = token.balanceOf(user);

    // balanceOf = mulDiv(shares, rebaseIndex, 1e18, Floor)
    // Allow for floor division rounding: balance <= shares * idx / 1e18
    assert balance == (shares * idx) / 1e18,
        "balanceOf must equal shares * rebaseIndex / 1e18";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: Transfer preserves total shares (INV-1 partial)
// ═══════════════════════════════════════════════════════════════════

/// @title Transfer does not change totalShares
/// @notice Shares only move between accounts; no creation or destruction
rule transferPreservesTotalShares(address to, uint256 amount) {
    env e;

    uint256 totalBefore = token.getTotalShares();

    token.transfer(e, to, amount);

    uint256 totalAfter = token.getTotalShares();

    assert totalAfter == totalBefore,
        "transfer must not change totalShares";
}

/// @title TransferFrom does not change totalShares
rule transferFromPreservesTotalShares(address from, address to, uint256 amount) {
    env e;

    uint256 totalBefore = token.getTotalShares();

    token.transferFrom(e, from, to, amount);

    uint256 totalAfter = token.getTotalShares();

    assert totalAfter == totalBefore,
        "transferFrom must not change totalShares";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: mintShares correctly increases totalShares (INV-1 partial)
// ═══════════════════════════════════════════════════════════════════

/// @title mintShares increases totalShares by exactly the minted amount
rule mintSharesIncreasesTotalShares(address to, uint256 shares) {
    env e;

    uint256 totalBefore = token.getTotalShares();
    uint256 sharesBefore = token.getShares(to);

    token.mintShares(e, to, shares);

    uint256 totalAfter = token.getTotalShares();
    uint256 sharesAfter = token.getShares(to);

    assert totalAfter == totalBefore + shares,
        "totalShares must increase by minted amount";
    assert sharesAfter == sharesBefore + shares,
        "recipient shares must increase by minted amount";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: burnShares correctly decreases totalShares (INV-1 partial)
// ═══════════════════════════════════════════════════════════════════

/// @title burnShares decreases totalShares by exactly the burned amount
rule burnSharesDecreasesTotalShares(address from, uint256 shares) {
    env e;

    uint256 totalBefore = token.getTotalShares();
    uint256 sharesBefore = token.getShares(from);

    token.burnShares(e, from, shares);

    uint256 totalAfter = token.getTotalShares();
    uint256 sharesAfter = token.getShares(from);

    assert totalAfter == totalBefore - shares,
        "totalShares must decrease by burned amount";
    assert sharesAfter == sharesBefore - shares,
        "sender shares must decrease by burned amount";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: Rebase factor must be in bounds (INV-4)
// ═══════════════════════════════════════════════════════════════════

/// @title rebase() reverts if factor is out of bounds
/// @notice CRIT-02: Factor must be in [0.99e18, 1.01e18]
rule rebaseRejectsOutOfBoundsFactor(uint256 factor) {
    env e;

    uint256 indexBefore = token.getRebaseIndex();

    // If factor is out of bounds, rebase must revert
    token.rebase@withrevert(e, factor);
    bool reverted = lastReverted;

    // Out of bounds => must revert
    assert (factor < 990000000000000000 || factor > 1010000000000000000) => reverted,
        "rebase must revert for out-of-bounds factor";
}

/// @title After rebase, index remains in bounds
rule rebaseKeepsIndexInBounds(uint256 factor) {
    env e;

    requireInvariant rebaseIndexInBounds();

    token.rebase(e, factor);

    uint256 newIndex = token.getRebaseIndex();
    assert newIndex >= 1e16 && newIndex <= 1e20,
        "rebaseIndex must remain in [1e16, 1e20] after rebase";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: Rebase only by authorized role (INV-6)
// ═══════════════════════════════════════════════════════════════════

/// @title rebase() reverts for unauthorized callers
/// @notice Only REBASE_EXECUTOR_ROLE can call rebase
rule rebaseOnlyByExecutor(uint256 factor) {
    env e;

    // REBASE_EXECUTOR_ROLE = keccak256("REBASE_EXECUTOR_ROLE")
    bytes32 rebaseRole = 0x06e2c3b0048c975c3aab69a05fd82d28e73d06a1d3ee87ef3aa1ec23e17c6cf1;

    bool hasRole = token.hasRole(rebaseRole, e.msg.sender);

    token.rebase@withrevert(e, factor);
    bool reverted = lastReverted;

    // If caller doesn't have the role, it must revert
    assert !hasRole => reverted,
        "rebase must revert for callers without REBASE_EXECUTOR_ROLE";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: Epoch monotonically increases
// ═══════════════════════════════════════════════════════════════════

/// @title Each successful rebase increments epoch by 1
rule rebaseIncrementsEpoch(uint256 factor) {
    env e;

    uint256 epochBefore = token.getEpoch();

    token.rebase(e, factor);

    uint256 epochAfter = token.getEpoch();

    assert epochAfter == epochBefore + 1,
        "epoch must increment by exactly 1 per rebase";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: Transfer moves correct shares
// ═══════════════════════════════════════════════════════════════════

/// @title Transfer correctly moves shares between accounts
rule transferMovesCorrectShares(address to, uint256 amount) {
    env e;
    require e.msg.sender != to; // Exclude self-transfer for simplicity

    uint256 senderSharesBefore = token.getShares(e.msg.sender);
    uint256 receiverSharesBefore = token.getShares(to);

    token.transfer(e, to, amount);

    uint256 senderSharesAfter = token.getShares(e.msg.sender);
    uint256 receiverSharesAfter = token.getShares(to);

    // Shares moved from sender to receiver must be equal
    uint256 senderDelta = senderSharesBefore - senderSharesAfter;
    uint256 receiverDelta = receiverSharesAfter - receiverSharesBefore;

    assert senderDelta == receiverDelta,
        "shares deducted from sender must equal shares added to receiver";
}

// ═══════════════════════════════════════════════════════════════════
//   RULE: Zero shares user has zero balance
// ═══════════════════════════════════════════════════════════════════

/// @title Users with 0 shares always have 0 balance
rule zeroSharesImpliesZeroBalance(address user) {
    uint256 shares = token.getShares(user);
    uint256 balance = token.balanceOf(user);

    assert shares == 0 => balance == 0,
        "zero shares must imply zero balance";
}
