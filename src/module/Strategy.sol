// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IERC4626} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";
// contracts
import {Shared} from "../common/Shared.sol";
// libs
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StorageLib as Storage, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {AmountCapLib, AmountCap} from "../lib/AmountCapLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";

/// @title StrategyModule contract
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
abstract contract StrategyModule is Shared {
    using SafeCast for uint256;
    using AmountCapLib for AmountCap;

    // max cap amount, which is the same as the max amount Strategy.allocated can hold.
    uint256 public constant MAX_CAP_AMOUNT = type(uint120).max;

    /// @notice Adjust a certain strategy's allocation points.
    /// @dev Can only be called by an address that have the `GUARDIAN` role.
    /// @param _strategy address of strategy
    /// @param _newPoints new strategy's points
    function adjustAllocationPoints(address _strategy, uint256 _newPoints) public virtual nonReentrant {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        IEulerAggregationVault.Strategy memory strategyDataCache = $.strategies[_strategy];

        if (strategyDataCache.status != IEulerAggregationVault.StrategyStatus.Active) {
            revert Errors.StrategyShouldBeActive();
        }

        if (_strategy == address(0) && _newPoints == 0) {
            revert Errors.InvalidAllocationPoints();
        }

        $.strategies[_strategy].allocationPoints = _newPoints.toUint96();
        $.totalAllocationPoints = $.totalAllocationPoints + _newPoints - strategyDataCache.allocationPoints;

        emit Events.AdjustAllocationPoints(_strategy, strategyDataCache.allocationPoints, _newPoints);
    }

    /// @notice Set cap on strategy allocated amount.
    /// @dev Can only be called by an address with the `GUARDIAN` role.
    ///      By default, cap is set to 0.
    /// @param _strategy Strategy address.
    /// @param _cap Cap amount
    function setStrategyCap(address _strategy, uint16 _cap) public virtual nonReentrant {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        if ($.strategies[_strategy].status != IEulerAggregationVault.StrategyStatus.Active) {
            revert Errors.StrategyShouldBeActive();
        }

        if (_strategy == address(0)) {
            revert Errors.NoCapOnCashReserveStrategy();
        }

        AmountCap strategyCap = AmountCap.wrap(_cap);
        // The raw uint16 cap amount == 0 is a special value. See comments in AmountCapLib.sol
        // Max cap is max amount that can be allocated into strategy (max uint120).
        if (_cap != 0 && strategyCap.resolve() > MAX_CAP_AMOUNT) revert Errors.StrategyCapExceedMax();

        $.strategies[_strategy].cap = strategyCap;

        emit Events.SetStrategyCap(_strategy, _cap);
    }

    /// @notice Toggle a strategy status between `Active` and `Emergency`.
    /// @dev Can only get called by an address with the `GUARDIAN` role.
    /// @dev This should be used as a circuit-breaker to exclude a faulty strategy from being harvest or rebalanced.
    /// It also deduct all the deposited amounts into the strategy as loss, and uses a loss socialization mechanism.
    /// This is needed, in case the aggregation vault can no longer withdraw from a certain strategy.
    /// In the case of switching a strategy from Emergency to Active again, the max withdrawable amount from the strategy
    /// will be set as the allocated amount, and will be immediately available to gulp.
    function toggleStrategyEmergencyStatus(address _strategy) public virtual nonReentrant {
        if (_strategy == address(0)) revert Errors.CanNotToggleStrategyEmergencyStatus();

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        IEulerAggregationVault.Strategy memory strategyCached = $.strategies[_strategy];

        if (strategyCached.status == IEulerAggregationVault.StrategyStatus.Inactive) {
            revert Errors.InactiveStrategy();
        } else if (strategyCached.status == IEulerAggregationVault.StrategyStatus.Active) {
            $.strategies[_strategy].status = IEulerAggregationVault.StrategyStatus.Emergency;

            // we should deduct loss before decrease totalAllocated to not underflow
            _deductLoss(strategyCached.allocated);

            $.totalAllocationPoints -= strategyCached.allocationPoints;
            $.totalAllocated -= strategyCached.allocated;

            _gulp();

            emit Events.ToggleStrategyEmergencyStatus(_strategy, true);
        } else {
            // Use `previewRedeem()` to get the actual assets amount, bypassing any limits or revert.
            uint256 aggregatorShares = IERC4626(_strategy).balanceOf(address(this));
            uint256 aggregatorAssets = IERC4626(_strategy).previewRedeem(aggregatorShares);

            $.strategies[_strategy].status = IEulerAggregationVault.StrategyStatus.Active;
            $.strategies[_strategy].allocated = aggregatorAssets.toUint120();

            $.totalAllocationPoints += strategyCached.allocationPoints;
            $.totalAllocated += aggregatorAssets;

            emit Events.ToggleStrategyEmergencyStatus(_strategy, false);
        }
    }

    /// @notice Add new strategy with its allocation points.
    /// @dev Can only be called by an address that have `STRATEGY_OPERATOR` role.
    /// @param _strategy Address of the strategy
    /// @param _allocationPoints Strategy's allocation points
    function addStrategy(address _strategy, uint256 _allocationPoints) public virtual nonReentrant {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        if ($.strategies[_strategy].status != IEulerAggregationVault.StrategyStatus.Inactive) {
            revert Errors.StrategyAlreadyExist();
        }

        if (IERC4626(_strategy).asset() != IERC4626(address(this)).asset()) {
            revert Errors.InvalidStrategyAsset();
        }

        if (_allocationPoints == 0) revert Errors.InvalidAllocationPoints();

        _callHooksTarget(ADD_STRATEGY, _msgSender());

        $.strategies[_strategy] = IEulerAggregationVault.Strategy({
            allocated: 0,
            allocationPoints: _allocationPoints.toUint96(),
            status: IEulerAggregationVault.StrategyStatus.Active,
            cap: AmountCap.wrap(0)
        });

        $.totalAllocationPoints += _allocationPoints;
        $.withdrawalQueue.push(_strategy);

        emit Events.AddStrategy(_strategy, _allocationPoints);
    }

    /// @notice Remove strategy and set its allocation points to zero.
    /// @dev Can only be called by an address that have the `STRATEGY_OPERATOR` role.
    /// A faulty strategy that has an allocated amount can not be removed, instead the strategy status
    /// should be set as `EMERGENCY` using `toggleStrategyEmergencyStatus()`.
    /// @param _strategy Address of the strategy to remove.
    function removeStrategy(address _strategy) public virtual nonReentrant {
        if (_strategy == address(0)) revert Errors.CanNotRemoveCashReserve();

        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();
        IEulerAggregationVault.Strategy storage strategyStorage = $.strategies[_strategy];

        if (strategyStorage.status != IEulerAggregationVault.StrategyStatus.Active) {
            revert Errors.StrategyShouldBeActive();
        }

        if (strategyStorage.allocated > 0) revert Errors.CanNotRemoveStrategyWithAllocatedAmount();

        _callHooksTarget(REMOVE_STRATEGY, _msgSender());

        $.totalAllocationPoints -= strategyStorage.allocationPoints;
        strategyStorage.status = IEulerAggregationVault.StrategyStatus.Inactive;
        strategyStorage.allocationPoints = 0;
        strategyStorage.cap = AmountCap.wrap(0);

        // remove from withdrawalQueue
        uint256 lastStrategyIndex = $.withdrawalQueue.length - 1;
        for (uint256 i = 0; i < lastStrategyIndex; ++i) {
            if ($.withdrawalQueue[i] == _strategy) {
                $.withdrawalQueue[i] = $.withdrawalQueue[lastStrategyIndex];

                break;
            }
        }
        $.withdrawalQueue.pop();

        emit Events.RemoveStrategy(_strategy);
    }

    /// @notice Get strategy params.
    /// @param _strategy strategy's address
    /// @return Strategy struct
    function getStrategy(address _strategy) public view returns (IEulerAggregationVault.Strategy memory) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.strategies[_strategy];
    }

    /// @notice Get the total allocation points.
    /// @return uint256 Total allocation points.
    function totalAllocationPoints() public view returns (uint256) {
        AggregationVaultStorage storage $ = Storage._getAggregationVaultStorage();

        return $.totalAllocationPoints;
    }
}

contract Strategy is StrategyModule {
    constructor(address _evc) Shared(_evc) {}
}
