// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OszillorFees} from "../../src/modules/OszillorFees.sol";

/// @title ConcreteOszillorFees
/// @notice Concrete instantiation of OszillorFees for testing.
contract ConcreteOszillorFees is OszillorFees {
    IERC20 public asset;

    constructor(address _asset, address _feeRecipient) {
        asset = IERC20(_asset);
        _initFees(_feeRecipient);
    }

    function collectFeeIfDue(uint256 totalAssets) external {
        _collectFeeIfDue(totalAssets);
    }

    function withdrawFees() external {
        _withdrawFees(asset);
    }

    function setFeeRate(uint256 newRateBps, uint256 totalAssets) external {
        _setFeeRate(newRateBps, totalAssets);
    }

    function calculateAccruedFee(uint256 totalAssets) external view returns (uint256) {
        return _calculateAccruedFee(totalAssets);
    }
}
