// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FourSixTwoSixAggBase, FourSixTwoSixAgg} from "../common/FourSixTwoSixAggBase.t.sol";

contract RemoveStrategyTest is FourSixTwoSixAggBase {
    uint256 strategyAllocationPoints;

    function setUp() public virtual override {
        super.setUp();

        strategyAllocationPoints = type(uint120).max;
        _addStrategy(manager, address(eTST), strategyAllocationPoints);
    }

    function testRemoveStrategy() public {
        uint256 totalAllocationPointsBefore = fourSixTwoSixAgg.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = fourSixTwoSixAgg.withdrawalQueueLength();

        vm.prank(manager);
        fourSixTwoSixAgg.removeStrategy(address(eTST));

        FourSixTwoSixAgg.Strategy memory strategyAfter = fourSixTwoSixAgg.getStrategy(address(eTST));

        assertEq(strategyAfter.active, false);
        assertEq(strategyAfter.allocationPoints, 0);
        assertEq(fourSixTwoSixAgg.totalAllocationPoints(), totalAllocationPointsBefore - strategyAllocationPoints);
        assertEq(fourSixTwoSixAgg.withdrawalQueueLength(), withdrawalQueueLengthBefore - 1);
    }

    function testRemoveStrategy_fromUnauthorized() public {
        vm.prank(deployer);
        vm.expectRevert();
        fourSixTwoSixAgg.removeStrategy(address(eTST));
    }

    function testRemoveStrategy_AlreadyRemoved() public {
        vm.prank(manager);
        vm.expectRevert();
        fourSixTwoSixAgg.removeStrategy(address(eTST2));
    }
}
