// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library EventsLib {
    /// @dev EulerAggregationVault events
    event Gulp(uint256 interestLeft, uint256 interestSmearEnd);
    event AccruePerformanceFee(address indexed feeRecipient, uint256 yield, uint256 feeShares);
    event Rebalance(address indexed strategy, uint256 amountToRebalance, bool isDeposit);
    event ExecuteHarvest(address indexed strategy, uint256 strategyBalanceAmount, uint256 strategyAllocatedAmount);
    event Harvest(uint256 totalAllocated, uint256 totlaYield, uint256 totalLoss);
    event SetWithdrawalQueue(address _oldWithdrawalQueuePlugin, address _newWithdrawalQueuePlugin);
    event SetRebalancer(address _oldRebalancer, address _newRebalancer);

    /// @dev Allocationpoints events
    event AdjustAllocationPoints(address indexed strategy, uint256 oldPoints, uint256 newPoints);
    event AddStrategy(address indexed strategy, uint256 allocationPoints);
    event RemoveStrategy(address indexed strategy);
    event SetStrategyCap(address indexed strategy, uint256 cap);

    /// @dev Fee events
    event SetFeeRecipient(address indexed oldRecipient, address indexed newRecipient);
    event SetPerformanceFee(uint256 oldFee, uint256 newFee);

    /// @dev Hooks events
    event SetHooksConfig(address indexed hooksTarget, uint32 hookedFns);

    /// @dev Rewards events
    event OptInStrategyRewards(address indexed strategy);
    event OptOutStrategyRewards(address indexed strategy);
    event EnableBalanceForwarder(address indexed user);
    event DisableBalanceForwarder(address indexed user);
    event EnableRewardForStrategy(address indexed strategy, address indexed reward);
    event DisableRewardForStrategy(address indexed strategy, address indexed reward, bool forfeitRecentReward);
}
