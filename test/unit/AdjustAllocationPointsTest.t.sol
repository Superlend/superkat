// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    IEulerAggregationLayer,
    ErrorsLib
} from "../common/EulerAggregationLayerBase.t.sol";

contract AdjustAllocationsPointsTest is EulerAggregationLayerBase {
    uint256 initialStrategyAllocationPoints = 500e18;

    function setUp() public virtual override {
        super.setUp();

        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testAdjustAllocationPoints() public {
        uint256 newAllocationPoints = 859e18;
        uint256 totalAllocationPointsBefore = eulerAggregationLayer.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerAggregationLayer.adjustAllocationPoints(address(eTST), newAllocationPoints);

        IEulerAggregationLayer.Strategy memory strategy = eulerAggregationLayer.getStrategy(address(eTST));

        assertEq(
            eulerAggregationLayer.totalAllocationPoints(),
            totalAllocationPointsBefore + (newAllocationPoints - initialStrategyAllocationPoints)
        );
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, newAllocationPoints);
    }

    function testAdjustAllocationPoints_FromUnauthorizedAddress() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(deployer);
        vm.expectRevert();
        eulerAggregationLayer.adjustAllocationPoints(address(eTST), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustAllocationPoints_InactiveStrategy() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        eulerAggregationLayer.adjustAllocationPoints(address(eTST2), newAllocationPoints);
        vm.stopPrank();
    }
}
