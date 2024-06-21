// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Strategy} from "../lib/StorageLib.sol";

interface IAggregationLayerVault {
    function rebalance(address _strategy, uint256 _amountToRebalance, bool _isDeposit) external;
    function gulp() external;
    function harvest() external;
    function executeStrategyWithdraw(address _strategy, uint256 _withdrawAmount) external;
    function executeAggregationVaultWithdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) external;
    function getStrategy(address _strategy) external view returns (Strategy memory);
    function totalAllocationPoints() external view returns (uint256);
    function totalAllocated() external view returns (uint256);
    function totalAssetsAllocatable() external view returns (uint256);
}
