// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FourSixTwoSixAggBase, FourSixTwoSixAgg, Strategy} from "../common/FourSixTwoSixAggBase.t.sol";

contract AdjustAllocationsPointsFuzzTest is FourSixTwoSixAggBase {
    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testFuzzAdjustAllocationPoints(uint256 _newAllocationPoints) public {
        _newAllocationPoints = bound(_newAllocationPoints, 0, type(uint120).max);

        uint256 strategyAllocationPoints = (fourSixTwoSixAgg.getStrategy(address(eTST))).allocationPoints;
        uint256 totalAllocationPointsBefore = fourSixTwoSixAgg.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        fourSixTwoSixAgg.adjustAllocationPoints(address(eTST), _newAllocationPoints);

        Strategy memory strategy = fourSixTwoSixAgg.getStrategy(address(eTST));

        if (_newAllocationPoints < strategyAllocationPoints) {
            assertEq(
                fourSixTwoSixAgg.totalAllocationPoints(),
                totalAllocationPointsBefore - (strategyAllocationPoints - _newAllocationPoints)
            );
        } else {
            assertEq(
                fourSixTwoSixAgg.totalAllocationPoints(),
                totalAllocationPointsBefore + (_newAllocationPoints - strategyAllocationPoints)
            );
        }
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, _newAllocationPoints);
    }
}
