// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultStrategy} from "../../src/interfaces/IVaultStrategy.sol";

/// @title MockStrategy
/// @notice Minimal mock of IVaultStrategy for testing vault integration.
/// @dev Holds deposited WETH and returns it on withdrawToVault(). stakeEth() is a no-op
///      so tokens simply sit in the mock (simulating Lido staking without actual protocol).
contract MockStrategy is IVaultStrategy {
    IERC20 public asset;

    uint256 public lastRebalanceTarget;
    uint256 public rebalanceCallCount;
    uint256 private _totalValue;
    uint256 private _ethBal;
    uint256 private _stableBal;
    uint256 private _ethPct;

    constructor(address _asset) {
        asset = IERC20(_asset);
        _ethPct = 10_000; // default 100% ETH
    }

    function stakeEth(uint256) external {}
    function unstakeEth(uint256) external {}
    function hedgeToStable(uint256) external {}
    function unhedge(uint256) external {}

    function rebalance(uint256 targetEthPct) external {
        lastRebalanceTarget = targetEthPct;
        _ethPct = targetEthPct;
        rebalanceCallCount++;
    }

    function withdrawToVault(uint256 wethNeeded) external returns (uint256) {
        uint256 available = asset.balanceOf(address(this));
        uint256 toSend = wethNeeded > available ? available : wethNeeded;
        if (toSend > 0) asset.transfer(msg.sender, toSend);
        return toSend;
    }

    function totalValueInEth() external view returns (uint256) { return _totalValue; }
    function ethBalance() external view returns (uint256) { return _ethBal; }
    function stableBalance() external view returns (uint256) { return _stableBal; }
    function currentEthPct() external view returns (uint256) { return _ethPct; }

    // Test helpers
    function setTotalValue(uint256 val) external { _totalValue = val; }
    function setEthBalance(uint256 val) external { _ethBal = val; }
    function setStableBalance(uint256 val) external { _stableBal = val; }
    function setEthPct(uint256 val) external { _ethPct = val; }
}
