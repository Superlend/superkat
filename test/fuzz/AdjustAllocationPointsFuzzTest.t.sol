// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract AdjustAllocationsPointsFuzzTest is YieldAggregatorBase {
    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testFuzzAdjustAllocationPoints(uint256 _newAllocationPoints) public {
        _newAllocationPoints = bound(_newAllocationPoints, 1, type(uint96).max);

        uint256 strategyAllocationPoints = (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocationPoints;
        uint256 totalAllocationPointsBefore = eulerYieldAggregatorVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerYieldAggregatorVault.adjustAllocationPoints(address(eTST), _newAllocationPoints);

        IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(address(eTST));

        if (_newAllocationPoints < strategyAllocationPoints) {
            assertEq(
                eulerYieldAggregatorVault.totalAllocationPoints(),
                totalAllocationPointsBefore - (strategyAllocationPoints - _newAllocationPoints)
            );
        } else {
            assertEq(
                eulerYieldAggregatorVault.totalAllocationPoints(),
                totalAllocationPointsBefore + (_newAllocationPoints - strategyAllocationPoints)
            );
        }
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, _newAllocationPoints);
    }
}
