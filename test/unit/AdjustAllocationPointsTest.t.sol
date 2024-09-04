// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract AdjustAllocationsPointsTest is YieldAggregatorBase {
    uint256 initialStrategyAllocationPoints = 500e18;

    function setUp() public virtual override {
        super.setUp();

        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testAdjustAllocationPoints() public {
        uint256 newAllocationPoints = 859e18;
        uint256 totalAllocationPointsBefore = eulerYieldAggregatorVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerYieldAggregatorVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(address(eTST));

        assertEq(
            eulerYieldAggregatorVault.totalAllocationPoints(),
            totalAllocationPointsBefore + (newAllocationPoints - initialStrategyAllocationPoints)
        );
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, newAllocationPoints);
    }

    function testAdjustAllocationPoints_FromUnauthorizedAddress() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(deployer);
        vm.expectRevert();
        eulerYieldAggregatorVault.adjustAllocationPoints(address(eTST), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustAllocationPoints_InactiveStrategy() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerYieldAggregatorVault.adjustAllocationPoints(address(eTST2), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustCashReserveAllocationPoints_ZeroPoints() public {
        uint256 newAllocationPoints = 0;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidAllocationPoints.selector);
        eulerYieldAggregatorVault.adjustAllocationPoints(address(0), newAllocationPoints);
        vm.stopPrank();
    }
}
