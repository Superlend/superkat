// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IEulerAggregationLayer {
    /// @dev Struct to pass init() call params.
    struct InitParams {
        address evc;
        address balanceTracker;
        address withdrawalQueuePlugin;
        address rebalancerPlugin;
        address aggregationVaultOwner;
        address asset;
        string name;
        string symbol;
        uint256 initialCashAllocationPoints;
    }

    /// @dev A struct that hold a strategy allocation's config
    /// allocated: amount of asset deposited into strategy
    /// allocationPoints: number of points allocated to this strategy
    /// active: a boolean to indice if this strategy is active or not
    /// cap: an optional cap in terms of deposited underlying asset. By default, it is set to 0(not activated)
    struct Strategy {
        uint120 allocated;
        uint120 allocationPoints;
        bool active;
        uint120 cap;
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

    function rebalance(address _strategy, uint256 _amountToRebalance, bool _isDeposit) external;
    function gulp() external;
    function harvest() external;
    function executeStrategyWithdraw(address _strategy, uint256 _withdrawAmount) external;
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
