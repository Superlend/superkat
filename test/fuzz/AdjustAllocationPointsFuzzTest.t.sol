// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    IAggregationLayerVault
} from "../common/AggregationLayerVaultBase.t.sol";

contract AdjustAllocationsPointsFuzzTest is AggregationLayerVaultBase {
    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testFuzzAdjustAllocationPoints(uint256 _newAllocationPoints) public {
        _newAllocationPoints = bound(_newAllocationPoints, 0, type(uint120).max);

        uint256 strategyAllocationPoints = (aggregationLayerVault.getStrategy(address(eTST))).allocationPoints;
        uint256 totalAllocationPointsBefore = aggregationLayerVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        aggregationLayerVault.adjustAllocationPoints(address(eTST), _newAllocationPoints);

        IAggregationLayerVault.Strategy memory strategy = aggregationLayerVault.getStrategy(address(eTST));

        if (_newAllocationPoints < strategyAllocationPoints) {
            assertEq(
                aggregationLayerVault.totalAllocationPoints(),
                totalAllocationPointsBefore - (strategyAllocationPoints - _newAllocationPoints)
            );
        } else {
            assertEq(
                aggregationLayerVault.totalAllocationPoints(),
                totalAllocationPointsBefore + (_newAllocationPoints - strategyAllocationPoints)
            );
        }
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, _newAllocationPoints);
    }
}
