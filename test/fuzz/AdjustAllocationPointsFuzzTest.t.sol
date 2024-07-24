// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    IEulerAggregationVault
} from "../common/EulerAggregationVaultBase.t.sol";

contract AdjustAllocationsPointsFuzzTest is EulerAggregationVaultBase {
    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testFuzzAdjustAllocationPoints(uint256 _newAllocationPoints) public {
        _newAllocationPoints = bound(_newAllocationPoints, 1, type(uint96).max);

        uint256 strategyAllocationPoints = (eulerAggregationVault.getStrategy(address(eTST))).allocationPoints;
        uint256 totalAllocationPointsBefore = eulerAggregationVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerAggregationVault.adjustAllocationPoints(address(eTST), _newAllocationPoints);

        IEulerAggregationVault.Strategy memory strategy = eulerAggregationVault.getStrategy(address(eTST));

        if (_newAllocationPoints < strategyAllocationPoints) {
            assertEq(
                eulerAggregationVault.totalAllocationPoints(),
                totalAllocationPointsBefore - (strategyAllocationPoints - _newAllocationPoints)
            );
        } else {
            assertEq(
                eulerAggregationVault.totalAllocationPoints(),
                totalAllocationPointsBefore + (_newAllocationPoints - strategyAllocationPoints)
            );
        }
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, _newAllocationPoints);
    }
}
