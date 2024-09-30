// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract AdjustAllocationsPointsTest is EulerEarnBase {
    uint256 initialStrategyAllocationPoints = 500e18;

    function setUp() public virtual override {
        super.setUp();

        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testAdjustAllocationPoints() public {
        uint256 newAllocationPoints = 859e18;
        uint256 totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerEulerEarnVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(
            eulerEulerEarnVault.totalAllocationPoints(),
            totalAllocationPointsBefore + (newAllocationPoints - initialStrategyAllocationPoints)
        );
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, newAllocationPoints);
    }

    function testAdjustAllocationPoints_FromUnauthorizedAddress() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(deployer);
        vm.expectRevert();
        eulerEulerEarnVault.adjustAllocationPoints(address(eTST), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustAllocationPoints_InactiveStrategy() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerEulerEarnVault.adjustAllocationPoints(address(eTST2), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustCashReserveAllocationPoints_ZeroPoints() public {
        uint256 newAllocationPoints = 0;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InvalidAllocationPoints.selector);
        eulerEulerEarnVault.adjustAllocationPoints(address(0), newAllocationPoints);
        vm.stopPrank();
    }
}
