// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    IEulerAggregationLayer
} from "../common/EulerAggregationLayerBase.t.sol";

contract AdjustAllocationsPointsFuzzTest is EulerAggregationLayerBase {
    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testFuzzAdjustAllocationPoints(uint256 _newAllocationPoints) public {
        _newAllocationPoints = bound(_newAllocationPoints, 0, type(uint120).max);

        uint256 strategyAllocationPoints = (eulerAggregationLayer.getStrategy(address(eTST))).allocationPoints;
        uint256 totalAllocationPointsBefore = eulerAggregationLayer.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerAggregationLayer.adjustAllocationPoints(address(eTST), _newAllocationPoints);

        IEulerAggregationLayer.Strategy memory strategy = eulerAggregationLayer.getStrategy(address(eTST));

        if (_newAllocationPoints < strategyAllocationPoints) {
            assertEq(
                eulerAggregationLayer.totalAllocationPoints(),
                totalAllocationPointsBefore - (strategyAllocationPoints - _newAllocationPoints)
            );
        } else {
            assertEq(
                eulerAggregationLayer.totalAllocationPoints(),
                totalAllocationPointsBefore + (_newAllocationPoints - strategyAllocationPoints)
            );
        }
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, _newAllocationPoints);
    }
}
