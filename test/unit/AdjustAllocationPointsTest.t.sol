// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    Strategy,
    ErrorsLib
} from "../common/AggregationLayerVaultBase.t.sol";

contract AdjustAllocationsPointsTest is AggregationLayerVaultBase {
    uint256 initialStrategyAllocationPoints = 500e18;

    function setUp() public virtual override {
        super.setUp();

        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testAdjustAllocationPoints() public {
        uint256 newAllocationPoints = 859e18;
        uint256 totalAllocationPointsBefore = aggregationLayerVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        aggregationLayerVault.adjustAllocationPoints(address(eTST), newAllocationPoints);

        Strategy memory strategy = aggregationLayerVault.getStrategy(address(eTST));

        assertEq(
            aggregationLayerVault.totalAllocationPoints(),
            totalAllocationPointsBefore + (newAllocationPoints - initialStrategyAllocationPoints)
        );
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, newAllocationPoints);
    }

    function testAdjustAllocationPoints_FromUnauthorizedAddress() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(deployer);
        vm.expectRevert();
        aggregationLayerVault.adjustAllocationPoints(address(eTST), newAllocationPoints);
        vm.stopPrank();
    }

    function testAdjustAllocationPoints_InactiveStrategy() public {
        uint256 newAllocationPoints = 859e18;

        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        aggregationLayerVault.adjustAllocationPoints(address(eTST2), newAllocationPoints);
        vm.stopPrank();
    }
}
