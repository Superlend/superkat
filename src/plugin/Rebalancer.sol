// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IAggregationLayerVault} from "../interface/IAggregationLayerVault.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title Rebalancer plugin
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice A contract to execute rebalance() on the AggregationLayerVault.
/// @dev Usually this contract will hold the `REBALANCER` role.
contract Rebalancer {
    event ExecuteRebalance(
        address indexed curatedVault,
        address indexed strategy,
        uint256 currentAllocation,
        uint256 targetAllocation,
        uint256 amountToRebalance
    );

    /// @notice Rebalance strategies allocation for a specific curated vault.
    /// @param _curatedVault Curated vault address.
    /// @param _strategies Strategies addresses.
    function executeRebalance(address _curatedVault, address[] calldata _strategies) external {
        IAggregationLayerVault(_curatedVault).gulp();

        for (uint256 i; i < _strategies.length; ++i) {
            _rebalance(_curatedVault, _strategies[i]);
        }
    }

    /// @dev If current allocation is greater than target allocation, the aggregator will withdraw the excess assets.
    ///      If current allocation is less than target allocation, the aggregator will:
    ///         - Try to deposit the delta, if the cash is not sufficient, deposit all the available cash
    ///         - If all the available cash is greater than the max deposit, deposit the max deposit
    /// @param _curatedVault Curated vault address.
    /// @param _strategy Strategy address.
    function _rebalance(address _curatedVault, address _strategy) private {
        if (_strategy == address(0)) {
            return; //nothing to rebalance as that's the cash reserve
        }

        IAggregationLayerVault.Strategy memory strategyData =
            IAggregationLayerVault(_curatedVault).getStrategy(_strategy);

        uint256 totalAllocationPointsCache = IAggregationLayerVault(_curatedVault).totalAllocationPoints();
        uint256 totalAssetsAllocatableCache = IAggregationLayerVault(_curatedVault).totalAssetsAllocatable();
        uint256 targetAllocation =
            totalAssetsAllocatableCache * strategyData.allocationPoints / totalAllocationPointsCache;

        if ((strategyData.cap > 0) && (targetAllocation > strategyData.cap)) targetAllocation = strategyData.cap;

        uint256 amountToRebalance;
        bool isDeposit;
        if (strategyData.allocated > targetAllocation) {
            // Withdraw
            amountToRebalance = strategyData.allocated - targetAllocation;

            uint256 maxWithdraw = IERC4626(_strategy).maxWithdraw(_curatedVault);
            if (amountToRebalance > maxWithdraw) {
                amountToRebalance = maxWithdraw;
            }

            isDeposit = false;
        } else if (strategyData.allocated < targetAllocation) {
            // Deposit
            uint256 targetCash = totalAssetsAllocatableCache
                * IAggregationLayerVault(_curatedVault).getStrategy(address(0)).allocationPoints
                / totalAllocationPointsCache;
            uint256 currentCash = totalAssetsAllocatableCache - IAggregationLayerVault(_curatedVault).totalAllocated();

            // Calculate available cash to put in strategies
            uint256 cashAvailable = (currentCash > targetCash) ? currentCash - targetCash : 0;

            amountToRebalance = targetAllocation - strategyData.allocated;
            if (amountToRebalance > cashAvailable) {
                amountToRebalance = cashAvailable;
            }

            uint256 maxDeposit = IERC4626(_strategy).maxDeposit(_curatedVault);
            if (amountToRebalance > maxDeposit) {
                amountToRebalance = maxDeposit;
            }

            if (amountToRebalance == 0) {
                return; // No cash to deposit
            }

            isDeposit = true;
        }

        IAggregationLayerVault(_curatedVault).rebalance(_strategy, amountToRebalance, isDeposit);

        emit ExecuteRebalance(_curatedVault, _strategy, strategyData.allocated, targetAllocation, amountToRebalance);
    }
}
