// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    IEulerAggregationVault,
    ErrorsLib
} from "../common/EulerAggregationVaultBase.t.sol";

contract AdjustAllocationsPointsTest is EulerAggregationVaultBase {
    uint256 initialStrategyAllocationPoints = 500e18;

    function setUp() public virtual override {
        super.setUp();

        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testAdjustAllocationPoints() public {
        uint256 newAllocationPoints = 859e18;
        uint256 totalAllocationPointsBefore = eulerAggregationVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerAggregationVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        IEulerAggregationVault.Strategy memory strategy = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(
            eulerAggregationVault.totalAllocationPoints(),
            totalAllocationPointsBefore + (newAllocationPoints - initialStrategyAllocationPoints)
        );
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, newAllocationPoints);
    }

    function testAdjustAllocationPoints_FromUnauthorizedAddress() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(deployer);
        vm.expectRevert();
        eulerAggregationVault.adjustAllocationPoints(address(eTST), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustAllocationPoints_InactiveStrategy() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.CanNotAdjustAllocationPoints.selector);
        eulerAggregationVault.adjustAllocationPoints(address(eTST2), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustCashReserveAllocationPoints_ZeroPoints() public {
        uint256 newAllocationPoints = 0;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidAllocationPoints.selector);
        eulerAggregationVault.adjustAllocationPoints(address(0), newAllocationPoints);
        vm.stopPrank();
    }
}
