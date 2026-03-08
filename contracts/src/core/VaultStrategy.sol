// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/interfaces/ISwapRouter.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

import {IVaultStrategy} from "../interfaces/IVaultStrategy.sol";
import {OszillorErrors} from "../libraries/OszillorErrors.sol";
import {Roles} from "../libraries/Roles.sol";

/// @title VaultStrategy
/// @author Hitesh (vyqno)
/// @notice Manages OSZILLOR v2 vault positions: Lido stETH staking + Uniswap V3 ETH↔USDC hedging.
/// @dev Only the vault (STRATEGY_MANAGER_ROLE) can call mutative functions.
///      Slippage protection uses Chainlink ETH/USD feed — never spot price.
///      V2-01: Fund isolation via access control.
///      V2-02: MAX_SLIPPAGE_BPS = 100 (1%) on all swaps.
///      V2-03: stETH treated as 1:1 with ETH (conservative assumption).
contract VaultStrategy is IVaultStrategy, AccessControl {
    using SafeERC20 for IERC20;

    // ──────────────────── Constants ────────────────────

    /// @notice Maximum slippage allowed on Uniswap swaps (1%).
    uint256 public constant MAX_SLIPPAGE_BPS = 100;

    /// @notice Basis point denominator.
    uint256 public constant BPS = 10_000;

    /// @notice Maximum staleness for the Chainlink price feed (1 hour).
    uint256 public constant MAX_FEED_STALENESS = 1 hours;

    /// @notice Maximum swap deadline offset from block.timestamp (HIGH-NEW-02 fix).
    uint256 public constant SWAP_DEADLINE_OFFSET = 300; // 5 minutes

    /// @notice Uniswap V3 pool fee tier for WETH/USDC (0.3%).
    uint24 public constant POOL_FEE = 3000;

    /// @notice USDC has 6 decimals.
    uint256 public constant USDC_DECIMALS = 6;

    /// @notice ETH has 18 decimals.
    uint256 public constant ETH_DECIMALS = 18;

    // ──────────────────── Immutable ────────────────────

    IERC20 public immutable weth;
    IERC20 public immutable usdc;
    IERC20 public immutable lido; // stETH token
    ISwapRouter public immutable uniRouter;
    AggregatorV3Interface public immutable ethUsdFeed;

    // ──────────────────── Events ────────────────────

    event Staked(uint256 wethAmount, uint256 stEthReceived);
    event Unstaked(uint256 stEthAmount, uint256 wethReceived);
    event HedgedToStable(uint256 wethIn, uint256 usdcOut);
    event Unhedged(uint256 usdcIn, uint256 wethOut);
    event RebalanceExecuted(uint256 targetEthPct, uint256 resultEthPct);
    event FundsReturnedToVault(uint256 wethSent);

    // ──────────────────── Constructor ────────────────────

    constructor(
        address _weth,
        address _usdc,
        address _lido,
        address _uniRouter,
        address _ethUsdFeed,
        address _admin
    ) {
        if (_weth == address(0) || _usdc == address(0) || _uniRouter == address(0)
            || _ethUsdFeed == address(0) || _admin == address(0)) {
            revert OszillorErrors.ZeroAddress();
        }

        weth = IERC20(_weth);
        usdc = IERC20(_usdc);
        lido = IERC20(_lido); // can be address(0) on Sepolia if using mock
        uniRouter = ISwapRouter(_uniRouter);
        ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    // ══════════════════════════════════════════════════════════════
    //                     STAKING (Lido)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IVaultStrategy
    /// @dev MED-NEW-02 fix: Validates lido address is non-zero before attempting transfer.
    function stakeEth(uint256 amount) external onlyRole(Roles.STRATEGY_MANAGER_ROLE) {
        if (amount == 0) revert OszillorErrors.ZeroAmount();
        if (address(lido) == address(0)) revert OszillorErrors.ZeroAddress();
        // In production: unwrap WETH → ETH → Lido.submit()
        // For Sepolia/testing: transfer WETH to lido mock which returns stETH
        uint256 stEthBefore = lido.balanceOf(address(this));
        weth.safeTransfer(address(lido), amount);
        uint256 stEthReceived = lido.balanceOf(address(this)) - stEthBefore;
        emit Staked(amount, stEthReceived);
    }

    /// @inheritdoc IVaultStrategy
    /// @dev MED-NEW-02 fix: Validates lido address is non-zero before attempting transfer.
    function unstakeEth(uint256 stEthAmount) external onlyRole(Roles.STRATEGY_MANAGER_ROLE) {
        if (stEthAmount == 0) revert OszillorErrors.ZeroAmount();
        if (address(lido) == address(0)) revert OszillorErrors.ZeroAddress();
        // In production: Lido withdrawal queue or secondary market
        // For Sepolia/testing: transfer stETH to lido mock which returns WETH
        uint256 wethBefore = weth.balanceOf(address(this));
        lido.safeTransfer(address(lido), stEthAmount);
        uint256 wethReceived = weth.balanceOf(address(this)) - wethBefore;
        emit Unstaked(stEthAmount, wethReceived);
    }

    // ══════════════════════════════════════════════════════════════
    //                     HEDGING (Uniswap V3)
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IVaultStrategy
    function hedgeToStable(uint256 ethAmount) external onlyRole(Roles.STRATEGY_MANAGER_ROLE) {
        if (ethAmount == 0) revert OszillorErrors.ZeroAmount();
        _swapWethToUsdc(ethAmount);
    }

    /// @inheritdoc IVaultStrategy
    function unhedge(uint256 usdcAmount) external onlyRole(Roles.STRATEGY_MANAGER_ROLE) {
        if (usdcAmount == 0) revert OszillorErrors.ZeroAmount();
        _swapUsdcToWeth(usdcAmount);
    }

    // ══════════════════════════════════════════════════════════════
    //                     REBALANCE
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IVaultStrategy
    function rebalance(uint256 targetEthPct) external onlyRole(Roles.STRATEGY_MANAGER_ROLE) {
        if (targetEthPct > BPS) revert OszillorErrors.InvalidTargetAllocation(targetEthPct);

        uint256 totalVal = _totalValueInEth();
        if (totalVal == 0) {
            emit RebalanceExecuted(targetEthPct, 0);
            return;
        }

        uint256 currentPct = _currentEthPct(totalVal);

        if (targetEthPct > currentPct) {
            // Need more ETH — swap USDC → WETH
            uint256 ethNeeded = (totalVal * (targetEthPct - currentPct)) / BPS;
            uint256 usdcToSwap = _ethToUsdc(ethNeeded);
            uint256 usdcAvailable = usdc.balanceOf(address(this));
            if (usdcToSwap > usdcAvailable) usdcToSwap = usdcAvailable;
            if (usdcToSwap > 0) _swapUsdcToWeth(usdcToSwap);
        } else if (targetEthPct < currentPct) {
            // Need less ETH — swap WETH → USDC (hedge)
            uint256 ethToReduce = (totalVal * (currentPct - targetEthPct)) / BPS;
            uint256 wethAvailable = weth.balanceOf(address(this));
            if (ethToReduce > wethAvailable) ethToReduce = wethAvailable;
            if (ethToReduce > 0) _swapWethToUsdc(ethToReduce);
        }

        emit RebalanceExecuted(targetEthPct, currentEthPct());
    }

    // ══════════════════════════════════════════════════════════════
    //                     VAULT LIQUIDITY
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IVaultStrategy
    function withdrawToVault(uint256 wethNeeded) external onlyRole(Roles.STRATEGY_MANAGER_ROLE) returns (uint256) {
        if (wethNeeded == 0) return 0;

        uint256 wethAvailable = weth.balanceOf(address(this));

        // If not enough idle WETH, unstake from Lido
        if (wethAvailable < wethNeeded && address(lido) != address(0)) {
            uint256 toUnstake = wethNeeded - wethAvailable;
            uint256 stEthBal = lido.balanceOf(address(this));
            if (toUnstake > stEthBal) toUnstake = stEthBal;
            if (toUnstake > 0) {
                uint256 wethBefore = weth.balanceOf(address(this));
                lido.safeTransfer(address(lido), toUnstake);
                wethAvailable = weth.balanceOf(address(this));
                emit Unstaked(toUnstake, wethAvailable - wethBefore);
            }
        }

        uint256 toSend = wethNeeded > wethAvailable ? wethAvailable : wethNeeded;
        if (toSend > 0) weth.safeTransfer(msg.sender, toSend);

        emit FundsReturnedToVault(toSend);
        return toSend;
    }

    // ══════════════════════════════════════════════════════════════
    //                     VIEW FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    /// @inheritdoc IVaultStrategy
    function totalValueInEth() external view returns (uint256) {
        return _totalValueInEth();
    }

    /// @inheritdoc IVaultStrategy
    function ethBalance() external view returns (uint256) {
        return _ethBalance();
    }

    /// @inheritdoc IVaultStrategy
    function stableBalance() external view returns (uint256) {
        return _usdcToEth(usdc.balanceOf(address(this)));
    }

    /// @inheritdoc IVaultStrategy
    function currentEthPct() public view returns (uint256) {
        uint256 totalVal = _totalValueInEth();
        if (totalVal == 0) return BPS; // Default to 100% ETH when empty
        return _currentEthPct(totalVal);
    }

    // ══════════════════════════════════════════════════════════════
    //                     INTERNAL — SWAPS
    // ══════════════════════════════════════════════════════════════

    function _swapWethToUsdc(uint256 wethAmount) internal {
        uint256 ethPrice = _getEthPrice();
        // Expected USDC out = wethAmount * ethPrice / 1e18 (adjust for USDC 6 decimals)
        // ethPrice is 8 decimals from Chainlink, wethAmount is 18 decimals
        // expectedOut = wethAmount * ethPrice / 1e(18 + 8 - 6) = wethAmount * ethPrice / 1e20
        uint256 expectedOut = (wethAmount * ethPrice) / 1e20;
        uint256 amountOutMin = (expectedOut * (BPS - MAX_SLIPPAGE_BPS)) / BPS;

        // MED-NEW-05 fix: Reset allowance to exact amount to prevent stale accumulation
        weth.forceApprove(address(uniRouter), wethAmount);

        // HIGH-NEW-02 fix: Use block.timestamp + offset instead of block.timestamp
        uint256 amountOut = uniRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(weth),
                tokenOut: address(usdc),
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp + SWAP_DEADLINE_OFFSET,
                amountIn: wethAmount,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        emit HedgedToStable(wethAmount, amountOut);
    }

    function _swapUsdcToWeth(uint256 usdcAmount) internal {
        uint256 ethPrice = _getEthPrice();
        // Expected WETH out = usdcAmount * 1e20 / ethPrice
        uint256 expectedOut = (usdcAmount * 1e20) / ethPrice;
        uint256 amountOutMin = (expectedOut * (BPS - MAX_SLIPPAGE_BPS)) / BPS;

        // MED-NEW-05 fix: Reset allowance to exact amount to prevent stale accumulation
        usdc.forceApprove(address(uniRouter), usdcAmount);

        // HIGH-NEW-02 fix: Use block.timestamp + offset instead of block.timestamp
        uint256 amountOut = uniRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(weth),
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp + SWAP_DEADLINE_OFFSET,
                amountIn: usdcAmount,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        emit Unhedged(usdcAmount, amountOut);
    }

    // ══════════════════════════════════════════════════════════════
    //                     INTERNAL — PRICE & NAV
    // ══════════════════════════════════════════════════════════════

    /// @dev Returns ETH/USD price with 8 decimals from Chainlink.
    function _getEthPrice() internal view returns (uint256) {
        (, int256 answer,, uint256 updatedAt,) = ethUsdFeed.latestRoundData();
        if (answer <= 0) revert OszillorErrors.StalePriceFeed(updatedAt, MAX_FEED_STALENESS);
        if (block.timestamp - updatedAt > MAX_FEED_STALENESS) {
            revert OszillorErrors.StalePriceFeed(updatedAt, MAX_FEED_STALENESS);
        }
        return uint256(answer); // 8 decimals
    }

    /// @dev Converts USDC amount to ETH terms using Chainlink feed.
    function _usdcToEth(uint256 usdcAmount) internal view returns (uint256) {
        if (usdcAmount == 0) return 0;
        uint256 ethPrice = _getEthPrice(); // 8 decimals
        // usdcAmount (6 dec) * 1e20 / ethPrice (8 dec) = ETH (18 dec)
        return (usdcAmount * 1e20) / ethPrice;
    }

    /// @dev Converts ETH amount to USDC terms using Chainlink feed.
    function _ethToUsdc(uint256 ethAmount) internal view returns (uint256) {
        if (ethAmount == 0) return 0;
        uint256 ethPrice = _getEthPrice(); // 8 decimals
        // ethAmount (18 dec) * ethPrice (8 dec) / 1e20 = USDC (6 dec)
        return (ethAmount * ethPrice) / 1e20;
    }

    /// @dev WETH + stETH balance (stETH treated as 1:1 with ETH, V2-03 conservative).
    function _ethBalance() internal view returns (uint256) {
        uint256 wethBal = weth.balanceOf(address(this));
        uint256 stEthBal = address(lido) != address(0) ? lido.balanceOf(address(this)) : 0;
        return wethBal + stEthBal;
    }

    /// @dev Total NAV in ETH terms.
    function _totalValueInEth() internal view returns (uint256) {
        return _ethBalance() + _usdcToEth(usdc.balanceOf(address(this)));
    }

    /// @dev Current ETH allocation in bps given total value.
    function _currentEthPct(uint256 totalVal) internal view returns (uint256) {
        if (totalVal == 0) return BPS;
        return (_ethBalance() * BPS) / totalVal;
    }
}
