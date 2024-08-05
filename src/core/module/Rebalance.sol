// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StorageLib, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {AmountCapLib, AmountCap} from "../lib/AmountCapLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";

abstract contract RebalanceModule is Shared {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;
    using AmountCapLib for AmountCap;

    /// @notice Rebalance strategies allocation for a specific curated vault.
    /// @param _strategies Strategies addresses.
    function rebalance(address[] calldata _strategies) external virtual nonReentrant {
        _gulp();

        for (uint256 i; i < _strategies.length; ++i) {
            _rebalance(_strategies[i]);
        }
    }

    /// @notice Rebalance strategy by depositing or withdrawing the amount to rebalance to hit target allocation.
    /// @dev If current allocation is greater than target allocation, the aggregator will withdraw the excess assets.
    ///      If current allocation is less than target allocation, the aggregator will:
    ///         - Try to deposit the delta, if the cash is not sufficient, deposit all the available cash
    ///         - If all the available cash is greater than the max deposit, deposit the max deposit
    /// @param _strategy Strategy address.
    function _rebalance(address _strategy) private {
        if (_strategy == address(0)) {
            return; //nothing to rebalance as that's the cash reserve
        }

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        IEulerAggregationVault.Strategy memory strategyData = $.strategies[_strategy];

        if (strategyData.status != IEulerAggregationVault.StrategyStatus.Active) return;

        uint256 totalAllocationPointsCache = $.totalAllocationPoints;
        uint256 totalAssetsAllocatableCache = _totalAssetsAllocatable();
        uint256 targetAllocation =
            totalAssetsAllocatableCache * strategyData.allocationPoints / totalAllocationPointsCache;

        uint120 capAmount = uint120(strategyData.cap.resolve());
        if ((AmountCap.unwrap(strategyData.cap) != 0) && (targetAllocation > capAmount)) targetAllocation = capAmount;

        uint256 amountToRebalance;
        bool isDeposit;
        if (strategyData.allocated > targetAllocation) {
            // Withdraw
            amountToRebalance = strategyData.allocated - targetAllocation;

            uint256 maxWithdraw = IERC4626(_strategy).maxWithdraw(address(this));
            if (amountToRebalance > maxWithdraw) {
                amountToRebalance = maxWithdraw;
            }
        } else if (strategyData.allocated < targetAllocation) {
            // Deposit
            uint256 targetCash =
                totalAssetsAllocatableCache * $.strategies[address(0)].allocationPoints / totalAllocationPointsCache;
            uint256 currentCash = totalAssetsAllocatableCache - $.totalAllocated;

            // Calculate available cash to put in strategies
            uint256 cashAvailable = (currentCash > targetCash) ? currentCash - targetCash : 0;

            amountToRebalance = targetAllocation - strategyData.allocated;
            if (amountToRebalance > cashAvailable) {
                amountToRebalance = cashAvailable;
            }

            uint256 maxDeposit = IERC4626(_strategy).maxDeposit(address(this));
            if (amountToRebalance > maxDeposit) {
                amountToRebalance = maxDeposit;
            }

            isDeposit = true;
        }

        if (amountToRebalance == 0) {
            return;
        }

        if (isDeposit) {
            // Do required approval (safely) and deposit
            IERC20(IERC4626(address(this)).asset()).safeIncreaseAllowance(_strategy, amountToRebalance);
            IERC4626(_strategy).deposit(amountToRebalance, address(this));
            $.strategies[_strategy].allocated = (strategyData.allocated + amountToRebalance).toUint120();
            $.totalAllocated += amountToRebalance;
        } else {
            IERC4626(_strategy).withdraw(amountToRebalance, address(this), address(this));
            $.strategies[_strategy].allocated = (strategyData.allocated - amountToRebalance).toUint120();
            $.totalAllocated -= amountToRebalance;
        }

        emit Events.Rebalance(_strategy, amountToRebalance, isDeposit);
    }
}

contract Rebalance is RebalanceModule {}
