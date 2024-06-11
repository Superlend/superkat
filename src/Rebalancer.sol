// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IFourSixTwoSixAgg} from "./interface/IFourSixTwoSixAgg.sol";
import {IERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";

contract Rebalancer {
    /// @notice Rebalance strategy allocation.
    /// @dev This function will first harvest yield, gulps and update interest.
    /// @dev If current allocation is greater than target allocation, the aggregator will withdraw the excess assets.
    ///      If current allocation is less than target allocation, the aggregator will:
    ///         - Try to deposit the delta, if the cash is not sufficient, deposit all the available cash
    ///         - If all the available cash is greater than the max deposit, deposit the max deposit
    function rebalance(address _curatedVault, address _strategy) external {
        _rebalance(_curatedVault, _strategy);
    }

    function rebalanceMultipleStrategies(address _curatedVault, address[] calldata strategies) external {
        for (uint256 i; i < strategies.length; ++i) {
            _rebalance(_curatedVault, strategies[i]);
        }
    }

    function _rebalance(address _curatedVault, address _strategy) private {
        if (_strategy == address(0)) {
            return; //nothing to rebalance as that's the cash reserve
        }

        // _callHookTarget(REBALANCE, _msgSender());

        IFourSixTwoSixAgg(_curatedVault).harvest(_strategy);

        IFourSixTwoSixAgg.Strategy memory strategyData = IFourSixTwoSixAgg(_curatedVault).getStrategy(_strategy);

        // no rebalance if strategy have an allocated amount greater than cap
        if ((strategyData.cap > 0) && (strategyData.allocated >= strategyData.cap)) return;

        uint256 totalAllocationPointsCache = IFourSixTwoSixAgg(_curatedVault).totalAllocationPoints();
        uint256 totalAssetsAllocatableCache = IFourSixTwoSixAgg(_curatedVault).totalAssetsAllocatable();
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
                * IFourSixTwoSixAgg(_curatedVault).getStrategy(address(0)).allocationPoints / totalAllocationPointsCache;
            uint256 currentCash = totalAssetsAllocatableCache - IFourSixTwoSixAgg(_curatedVault).totalAllocated();

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

        IFourSixTwoSixAgg(_curatedVault).rebalance(_strategy, amountToRebalance, isDeposit);

        // emit Rebalance(_strategy, strategyData.allocated, targetAllocation, amountToRebalance)
    }

    // /// @notice Rebalance strategy's allocation.
    // /// @param _strategy Address of strategy to rebalance.
    // function rebalance(address _strategy) external {
    //     _rebalance(_strategy);

    //     _gulp();
    // }
}
