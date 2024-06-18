// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library EventsLib {
    /// @dev FourSixTwoSixAgg events
    event Gulp(uint256 interestLeft, uint256 interestSmearEnd);
    event Harvest(address indexed strategy, uint256 strategyBalanceAmount, uint256 strategyAllocatedAmount);
    event AccruePerformanceFee(address indexed feeRecipient, uint256 yield, uint256 feeAssets);
    event Rebalance(address indexed strategy, uint256 _amountToRebalance, bool _isDeposit);

    /// @dev Allocationpoints events
    event AdjustAllocationPoints(address indexed strategy, uint256 oldPoints, uint256 newPoints);
    event AddStrategy(address indexed strategy, uint256 allocationPoints);
    event RemoveStrategy(address indexed _strategy);
    event SetStrategyCap(address indexed strategy, uint256 cap);

    /// @dev Fee events
    event SetFeeRecipient(address indexed oldRecipient, address indexed newRecipient);
    event SetPerformanceFee(uint256 oldFee, uint256 newFee);

    /// @dev Hooks events
    event SetHooksConfig(address indexed hooksTarget, uint32 hookedFns);

    /// @dev Rewards events
    event OptInStrategyRewards(address indexed strategy);
    event OptOutStrategyRewards(address indexed strategy);
    event EnableBalanceForwarder(address indexed _user);
    event DisableBalanceForwarder(address indexed _user);
}
