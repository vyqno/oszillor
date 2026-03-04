// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IOszillorToken} from "../interfaces/IOszillorToken.sol";

import {TokenPool} from "@chainlink/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {Pool} from "@chainlink/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IERC20} from
    "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

/// @title OszillorTokenPool
/// @author Hitesh (vyqno)
/// @notice CCIP token pool for share-based bridging of the OSZILLOR rebase token.
/// @dev HIGH-03 fix: Always bridges SHARES, not rebased amounts.
///      This pool extends Chainlink's TokenPool directly (not BurnMintTokenPoolAbstract)
///      because OszillorToken uses `mintShares()`/`burnShares()` instead of standard
///      `mint()`/`burn()` from IBurnMintERC20.
///
///      On lockOrBurn (source chain):
///        1. Convert CCIP amount to shares via token.sharesOf / math
///        2. Burn shares from the pool
///        3. Encode (localDecimals, rebaseIndex) in destPoolData for reconciliation
///
///      On releaseOrMint (destination chain):
///        1. Calculate local amount (handles cross-chain decimal differences)
///        2. Convert to shares using destination chain's rebaseIndex
///        3. Mint shares to receiver
///        4. Return actual balance change as destinationAmount
contract OszillorTokenPool is TokenPool {
    /// @notice The OSZILLOR rebase token (cast for share-based operations).
    IOszillorToken public immutable oszillorToken;

    /// @notice Emitted when shares are burned on the source chain.
    event SharesBurned(address indexed sender, uint256 shares, uint256 amount);

    /// @notice Emitted when shares are minted on the destination chain.
    event SharesMinted(address indexed receiver, uint256 shares, uint256 amount);

    error ZeroSharesBridged();

    /// @param token The OSZILLOR token address (must be the same IERC20 managed by this pool).
    /// @param allowlist Optional allowlist of addresses permitted to use lockOrBurn.
    /// @param rmnProxy Address of the CCIP RMN proxy.
    /// @param router Address of the CCIP Router.
    constructor(
        address token,
        address[] memory allowlist,
        address rmnProxy,
        address router
    ) TokenPool(IERC20(token), 18, allowlist, rmnProxy, router) {
        oszillorToken = IOszillorToken(token);
    }

    // ═══════════════════════════════════════════════════════════════
    //                       lockOrBurn (source)
    // ═══════════════════════════════════════════════════════════════

    /// @notice Burns shares on the source chain for CCIP bridging.
    /// @dev HIGH-03: Bridges shares, not rebased amounts.
    ///      The `lockOrBurnIn.amount` is in token amount (balanceOf units).
    ///      We convert to shares, burn them, and encode rebaseIndex in pool data.
    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external virtual override returns (Pool.LockOrBurnOutV1 memory) {
        _validateLockOrBurn(lockOrBurnIn);

        uint256 amount = lockOrBurnIn.amount;

        // Convert amount to shares using current rebaseIndex
        // shares = amount * 1e18 / rebaseIndex
        uint256 rebaseIdx = oszillorToken.rebaseIndex();
        uint256 shares = (amount * 1e18) / rebaseIdx;
        if (shares == 0) revert ZeroSharesBridged();

        // Burn shares from this pool (tokens were transferred to pool by CCIP infra)
        oszillorToken.burnShares(address(this), shares);

        emit SharesBurned(lockOrBurnIn.originalSender, shares, amount);
        emit Burned(msg.sender, amount);

        // Encode local decimals + rebaseIndex for destination reconciliation
        return Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(i_tokenDecimals, rebaseIdx)
        });
    }

    // ═══════════════════════════════════════════════════════════════
    //                     releaseOrMint (destination)
    // ═══════════════════════════════════════════════════════════════

    /// @notice Mints shares on the destination chain for CCIP bridging.
    /// @dev HIGH-03: Receives shares (encoded via source rebaseIndex),
    ///      mints using destination chain's rebaseIndex.
    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) external virtual override returns (Pool.ReleaseOrMintOutV1 memory) {
        _validateReleaseOrMint(releaseOrMintIn);

        // Calculate the local amount (handles decimal differences)
        uint256 localAmount = _calculateLocalAmount(
            releaseOrMintIn.amount,
            _parseRemoteDecimals(releaseOrMintIn.sourcePoolData)
        );

        // Convert amount to shares using LOCAL rebaseIndex
        uint256 rebaseIdx = oszillorToken.rebaseIndex();
        uint256 shares = (localAmount * 1e18) / rebaseIdx;
        if (shares == 0) revert ZeroSharesBridged();

        // Mint shares to receiver
        oszillorToken.mintShares(releaseOrMintIn.receiver, shares);

        // Calculate actual balance change (shares * rebaseIndex / 1e18)
        uint256 actualAmount = (shares * rebaseIdx) / 1e18;

        emit SharesMinted(releaseOrMintIn.receiver, shares, actualAmount);
        emit Minted(msg.sender, releaseOrMintIn.receiver, actualAmount);

        return Pool.ReleaseOrMintOutV1({destinationAmount: actualAmount});
    }

    /// @dev Override to parse our custom pool data format: (uint8 decimals, uint256 rebaseIndex).
    function _parseRemoteDecimals(
        bytes memory sourcePoolData
    ) internal view override returns (uint8) {
        if (sourcePoolData.length == 0) {
            return i_tokenDecimals;
        }
        // Our format: abi.encode(uint8, uint256) = 64 bytes
        if (sourcePoolData.length == 64) {
            (uint256 remoteDecimals, ) = abi.decode(sourcePoolData, (uint256, uint256));
            if (remoteDecimals > type(uint8).max) {
                revert InvalidRemoteChainDecimals(sourcePoolData);
            }
            return uint8(remoteDecimals);
        }
        // Fallback to standard parsing (32 bytes = just decimals)
        return super._parseRemoteDecimals(sourcePoolData);
    }
}
