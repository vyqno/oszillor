// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MockChainlinkFeed
/// @notice Mock AggregatorV3Interface for testing VaultStrategy price conversions.
contract MockChainlinkFeed {
    int256 private _price;
    uint256 private _updatedAt;
    uint8 private _decimals;

    constructor(int256 initialPrice) {
        _price = initialPrice;
        _updatedAt = block.timestamp;
        _decimals = 8; // Chainlink ETH/USD uses 8 decimals
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _price, _updatedAt, _updatedAt, 1);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // Test helpers
    function setPrice(int256 price) external {
        _price = price;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 ts) external {
        _updatedAt = ts;
    }
}
