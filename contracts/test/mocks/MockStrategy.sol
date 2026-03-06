// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IVaultStrategy} from "../../src/interfaces/IVaultStrategy.sol";

/// @title MockStrategy
/// @notice Minimal mock of IVaultStrategy for testing vault integration.
contract MockStrategy is IVaultStrategy {
    uint256 public lastRebalanceTarget;
    uint256 public rebalanceCallCount;
    uint256 private _totalValue;
    uint256 private _ethBal;
    uint256 private _stableBal;
    uint256 private _ethPct;

    constructor() {
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
