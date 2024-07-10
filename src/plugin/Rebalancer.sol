// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IEulerAggregationVault} from "../core/interface/IEulerAggregationVault.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title Rebalancer plugin
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A contract to execute rebalance() on the EulerAggregationVault.
contract Rebalancer {
    event ExecuteRebalance(
        address indexed curatedVault,
        address indexed strategy,
        uint256 currentAllocation,
        uint256 targetAllocation,
        uint256 amountToRebalance
    );

    /// @notice Rebalance strategies allocation for a specific curated vault.
    /// @param _aggregationVault Aggregation vault address.
    /// @param _strategies Strategies addresses.
    function executeRebalance(address _aggregationVault, address[] calldata _strategies) external {
        IEulerAggregationVault(_aggregationVault).gulp();

        for (uint256 i; i < _strategies.length; ++i) {
            _rebalance(_aggregationVault, _strategies[i]);
        }
    }

    /// @dev If current allocation is greater than target allocation, the aggregator will withdraw the excess assets.
    ///      If current allocation is less than target allocation, the aggregator will:
    ///         - Try to deposit the delta, if the cash is not sufficient, deposit all the available cash
    ///         - If all the available cash is greater than the max deposit, deposit the max deposit
    /// @param _aggregationVault Aggregation vault address.
    /// @param _strategy Strategy address.
    function _rebalance(address _aggregationVault, address _strategy) private {
        if (_strategy == address(0)) {
            return; //nothing to rebalance as that's the cash reserve
        }

        IEulerAggregationVault.Strategy memory strategyData =
            IEulerAggregationVault(_aggregationVault).getStrategy(_strategy);

        uint256 totalAllocationPointsCache = IEulerAggregationVault(_aggregationVault).totalAllocationPoints();
        uint256 totalAssetsAllocatableCache = IEulerAggregationVault(_aggregationVault).totalAssetsAllocatable();
        uint256 targetAllocation =
            totalAssetsAllocatableCache * strategyData.allocationPoints / totalAllocationPointsCache;

        if ((strategyData.cap > 0) && (targetAllocation > strategyData.cap)) targetAllocation = strategyData.cap;

        uint256 amountToRebalance;
        bool isDeposit;
        if (strategyData.allocated > targetAllocation) {
            // Withdraw
            amountToRebalance = strategyData.allocated - targetAllocation;

            uint256 maxWithdraw = IERC4626(_strategy).maxWithdraw(_aggregationVault);
            if (amountToRebalance > maxWithdraw) {
                amountToRebalance = maxWithdraw;
            }

            isDeposit = false;
        } else if (strategyData.allocated < targetAllocation) {
            // Deposit
            uint256 targetCash = totalAssetsAllocatableCache
                * IEulerAggregationVault(_aggregationVault).getStrategy(address(0)).allocationPoints
                / totalAllocationPointsCache;
            uint256 currentCash =
                totalAssetsAllocatableCache - IEulerAggregationVault(_aggregationVault).totalAllocated();

            // Calculate available cash to put in strategies
            uint256 cashAvailable = (currentCash > targetCash) ? currentCash - targetCash : 0;

            amountToRebalance = targetAllocation - strategyData.allocated;
            if (amountToRebalance > cashAvailable) {
                amountToRebalance = cashAvailable;
            }

            uint256 maxDeposit = IERC4626(_strategy).maxDeposit(_aggregationVault);
            if (amountToRebalance > maxDeposit) {
                amountToRebalance = maxDeposit;
            }

            if (amountToRebalance == 0) {
                return; // No cash to deposit
            }

            isDeposit = true;
        }

        IEulerAggregationVault(_aggregationVault).rebalance(_strategy, amountToRebalance, isDeposit);

        emit ExecuteRebalance(_aggregationVault, _strategy, strategyData.allocated, targetAllocation, amountToRebalance);
    }
}
