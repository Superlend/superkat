// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IFourSixTwoSixAgg {
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

    function rebalance(address _strategy, uint256 _amountToRebalance, bool _isDeposit) external;

    function getStrategy(address _strategy) external view returns (Strategy memory);
    function totalAllocationPoints() external view returns (uint256);
    function totalAllocated() external view returns (uint256);
    function totalAssetsAllocatable() external view returns (uint256);
}
