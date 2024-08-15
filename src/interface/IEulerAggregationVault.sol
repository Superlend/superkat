// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {AmountCap} from "../lib/AmountCapLib.sol";

interface IEulerAggregationVault {
    /// @dev Struct to pass to constructor.
    struct ConstructorParams {
        address evc;
        address aggregationVaultModule;
        address rewardsModule;
        address hooksModule;
        address feeModule;
        address strategyModule;
        address rebalanceModule;
        address withdrawalQueueModule;
    }

    /// @dev Struct to pass init() call params.
    struct InitParams {
        address aggregationVaultOwner;
        address asset;
        address balanceTracker;
        string name;
        string symbol;
        uint256 initialCashAllocationPoints;
    }

    /// @dev A struct that hold a strategy allocation's config
    /// allocated: amount of asset deposited into strategy
    /// allocationPoints: number of points allocated to this strategy
    /// cap: an optional cap in terms of deposited underlying asset. By default, it is set to 0(not activated)
    /// status: an enum describing the strategy status. Check the enum definition for more details.
    struct Strategy {
        uint120 allocated;
        uint96 allocationPoints;
        AmountCap cap;
        StrategyStatus status;
    }

    /// @dev An enum for strategy status.
    /// An inactive strategy is a strategy that is not added to and recognized by the withdrawal queue.
    /// An active strategy is a well-functional strategy that is added in the withdrawal queue, can be rebalanced and harvested.
    /// A strategy status set as Emergency, if when the strategy for some reasons can no longer be withdrawn from or deposited into it,
    /// this will be used as a circuit-breaker to ensure that the aggregation vault can continue functioning as intended,
    /// and the only impacted strategy will be the one set as Emergency.
    enum StrategyStatus {
        Inactive,
        Active,
        Emergency
    }

    function init(InitParams calldata _initParams) external;
    function gulp() external;
    function harvest() external;
    function getStrategy(address _strategy) external view returns (Strategy memory);
    function totalAllocationPoints() external view returns (uint256);
    function totalAllocated() external view returns (uint256);
    function totalAssetsAllocatable() external view returns (uint256);
}
