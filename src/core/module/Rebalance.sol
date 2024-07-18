// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IEulerAggregationVault} from "../interface/IEulerAggregationVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
// contracts
import {Shared} from "../common/Shared.sol";
import {ContextUpgradeable} from "@openzeppelin-upgradeable/utils/ContextUpgradeable.sol";
// libs
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {StorageLib, AggregationVaultStorage} from "../lib/StorageLib.sol";
import {ErrorsLib as Errors} from "../lib/ErrorsLib.sol";
import {EventsLib as Events} from "../lib/EventsLib.sol";

abstract contract RebalanceModule is ContextUpgradeable, Shared {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    /// @notice Rebalance strategy by depositing or withdrawing the amount to rebalance to hit target allocation.
    /// @dev Can only be called only by the WithdrawalQueue plugin.
    /// @param _strategy Strategy address.
    /// @param _amountToRebalance Amount to deposit or withdraw.
    /// @param _isDeposit bool to indicate if it is a deposit or a withdraw.
    function rebalance(address _strategy, uint256 _amountToRebalance, bool _isDeposit) external virtual nonReentrant {
        AggregationVaultStorage storage $ = StorageLib._getAggregationVaultStorage();

        if (_msgSender() != $.rebalancer) revert Errors.NotRebalancer();

        IEulerAggregationVault.Strategy memory strategyData = $.strategies[_strategy];

        if (strategyData.status != IEulerAggregationVault.StrategyStatus.Active) return;

        if (_isDeposit) {
            // Do required approval (safely) and deposit
            IERC20(IERC4626(address(this)).asset()).safeIncreaseAllowance(_strategy, _amountToRebalance);
            IERC4626(_strategy).deposit(_amountToRebalance, address(this));
            $.strategies[_strategy].allocated = (strategyData.allocated + _amountToRebalance).toUint120();
            $.totalAllocated += _amountToRebalance;
        } else {
            IERC4626(_strategy).withdraw(_amountToRebalance, address(this), address(this));
            $.strategies[_strategy].allocated = (strategyData.allocated - _amountToRebalance).toUint120();
            $.totalAllocated -= _amountToRebalance;
        }

        emit Events.Rebalance(_strategy, _amountToRebalance, _isDeposit);
    }
}

contract Rebalance is RebalanceModule {}
