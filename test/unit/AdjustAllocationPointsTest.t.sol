// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FourSixTwoSixAggBase, FourSixTwoSixAgg} from "../common/FourSixTwoSixAggBase.t.sol";

contract AdjustAllocationsPointsTest is FourSixTwoSixAggBase {
    uint256 initialStrategyAllocationPoints = 500e18;

    function setUp() public virtual override {
        super.setUp();

        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testAdjustAllocationPoints() public {
        uint256 newAllocationPoints = 859e18;
        uint256 totalAllocationPointsBefore = fourSixTwoSixAgg.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = fourSixTwoSixAgg.withdrawalQueueLength();

        vm.prank(manager);
        fourSixTwoSixAgg.adjustAllocationPoints(address(eTST), newAllocationPoints);

        FourSixTwoSixAgg.Strategy memory strategy = fourSixTwoSixAgg.getStrategy(address(eTST));

        assertEq(
            fourSixTwoSixAgg.totalAllocationPoints(),
            totalAllocationPointsBefore + (newAllocationPoints - initialStrategyAllocationPoints)
        );
        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, newAllocationPoints);
    }

    function testAdjustAllocationPoints_FromUnauthorizedAddress() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(deployer);
        vm.expectRevert();
        fourSixTwoSixAgg.adjustAllocationPoints(address(eTST), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustAllocationPoints_InactiveStrategy() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(manager);
        vm.expectRevert(FourSixTwoSixAgg.InactiveStrategy.selector);
        fourSixTwoSixAgg.adjustAllocationPoints(address(eTST2), newAllocationPoints);
        vm.stopPrank();
    }
}
