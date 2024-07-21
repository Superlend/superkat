// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IEulerAggregationVault {
    /// @dev Struct to pass to constrcutor.
    struct ConstructorParams {
        address rewardsModule;
        address hooksModule;
        address feeModule;
        address strategyModule;
        address rebalanceModule;
    }

    /// @dev Struct to pass init() call params.
    struct InitParams {
        address aggregationVaultOwner;
        address asset;
        address withdrawalQueuePlugin;
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
        uint120 allocationPoints;
        uint120 cap;
        StrategyStatus status;
    }

    /// @dev Euler saving rate struct
    /// @dev Based on https://github.com/euler-xyz/euler-vault-kit/blob/master/src/Synths/EulerSavingsRate.sol
    /// lastInterestUpdate: last timestamo where interest was updated.
    /// interestSmearEnd: timestamp when the smearing of interest end.
    /// interestLeft: amount of interest left to smear.
    /// locked: if locked or not for update.
    struct AggregationVaultSavingRate {
        uint40 lastInterestUpdate;
        uint40 interestSmearEnd;
        uint168 interestLeft;
        uint8 locked;
    }

    /// @dev An enum for strategy status.
    /// An inactive strategy is a strategy that is not added to and recognized by the withdrawal queue.
    /// An active startegy is a well-functional strategy that is added in the withdrawal queue, can be rebalanced and harvested.
    /// A strategy status set as Emeregncy, is when the strategy for some reasons can no longer be withdrawn from or deposited it,
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
    function executeStrategyWithdraw(address _strategy, uint256 _withdrawAmount) external returns (uint256);
    function executeAggregationVaultWithdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) external;
    function getStrategy(address _strategy) external view returns (Strategy memory);
    function totalAllocationPoints() external view returns (uint256);
    function totalAllocated() external view returns (uint256);
    function totalAssetsAllocatable() external view returns (uint256);
}
