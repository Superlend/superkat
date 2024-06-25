// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IWithdrawalQueue} from "../interface/IWithdrawalQueue.sol";
import {IAggregationLayerVault} from "../interface/IAggregationLayerVault.sol";
// contracts
import {Shared} from "../Shared.sol";
// libs
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StorageLib, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {ErrorsLib} from "../lib/ErrorsLib.sol";
import {EventsLib} from "../lib/EventsLib.sol";

/// @title FeeModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract AllocationPointsModule is Shared {
    using SafeCast for uint256;

    /// @notice Adjust a certain strategy's allocation points.
    /// @dev Can only be called by an address that have the ALLOCATIONS_MANAGER
    /// @param _strategy address of strategy
    /// @param _newPoints new strategy's points
    function adjustAllocationPoints(address _strategy, uint256 _newPoints) external virtual nonReentrant {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        IAggregationLayerVault.Strategy memory strategyDataCache = $.strategies[_strategy];

        if (!strategyDataCache.active) {
            revert ErrorsLib.InactiveStrategy();
        }

        $.strategies[_strategy].allocationPoints = _newPoints.toUint120();
        $.totalAllocationPoints = $.totalAllocationPoints + _newPoints - strategyDataCache.allocationPoints;

        emit EventsLib.AdjustAllocationPoints(_strategy, strategyDataCache.allocationPoints, _newPoints);
    }

    /// @notice Set cap on strategy allocated amount.
    /// @dev By default, cap is set to 0, not activated.
    /// @param _strategy Strategy address.
    /// @param _cap Cap amount
    function setStrategyCap(address _strategy, uint256 _cap) external virtual nonReentrant {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if (!$.strategies[_strategy].active) {
            revert ErrorsLib.InactiveStrategy();
        }

        $.strategies[_strategy].cap = _cap.toUint120();

        emit EventsLib.SetStrategyCap(_strategy, _cap);
    }

    /// @notice Add new strategy with it's allocation points.
    /// @dev Can only be called by an address that have STRATEGY_ADDER.
    /// @param _strategy Address of the strategy
    /// @param _allocationPoints Strategy's allocation points
    function addStrategy(address _strategy, uint256 _allocationPoints) external virtual nonReentrant {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if ($.strategies[_strategy].active) {
            revert ErrorsLib.StrategyAlreadyExist();
        }

        if (IERC4626(_strategy).asset() != IERC4626(address(this)).asset()) {
            revert ErrorsLib.InvalidStrategyAsset();
        }

        _callHooksTarget(ADD_STRATEGY, _msgSender());

        $.strategies[_strategy] = IAggregationLayerVault.Strategy({
            allocated: 0,
            allocationPoints: _allocationPoints.toUint120(),
            active: true,
            cap: 0
        });

        $.totalAllocationPoints += _allocationPoints;
        IWithdrawalQueue($.withdrawalQueue).addStrategyToWithdrawalQueue(_strategy);

        emit EventsLib.AddStrategy(_strategy, _allocationPoints);
    }

    /// @notice Remove strategy and set its allocation points to zero.
    /// @dev This function does not pull funds, `harvest()` needs to be called to withdraw
    /// @dev Can only be called by an address that have the STRATEGY_REMOVER
    /// @param _strategy Address of the strategy
    function removeStrategy(address _strategy) external virtual nonReentrant {
        if (_strategy == address(0)) revert ErrorsLib.CanNotRemoveCashReserve();

        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        IAggregationLayerVault.Strategy storage strategyStorage = $.strategies[_strategy];

        if (!strategyStorage.active) {
            revert ErrorsLib.AlreadyRemoved();
        }

        _callHooksTarget(REMOVE_STRATEGY, _msgSender());

        $.totalAllocationPoints -= strategyStorage.allocationPoints;
        strategyStorage.active = false;
        strategyStorage.allocationPoints = 0;

        // remove from withdrawalQueue
        IWithdrawalQueue($.withdrawalQueue).removeStrategyFromWithdrawalQueue(_strategy);

        emit EventsLib.RemoveStrategy(_strategy);
    }
}

contract AllocationPoints is AllocationPointsModule {}
