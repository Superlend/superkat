// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract AdjustAllocationsPointsFuzzTest is EulerEarnBase {
    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
    }

    function testFuzzAdjustAllocationPoints(uint256 _newAllocationPoints) public {
        _newAllocationPoints = bound(_newAllocationPoints, 1, type(uint96).max);

        uint256 strategyAllocationPoints = (eulerEulerEarnVault.getStrategy(address(eTST))).allocationPoints;
        uint256 totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();
        uint256 withdrawalQueueLengthBefore = _getWithdrawalQueueLength();

        vm.prank(manager);
        eulerEulerEarnVault.adjustAllocationPoints(address(eTST), _newAllocationPoints);

        IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(address(eTST));

        if (_newAllocationPoints < strategyAllocationPoints) {
            assertEq(
                eulerEulerEarnVault.totalAllocationPoints(),
                totalAllocationPointsBefore - (strategyAllocationPoints - _newAllocationPoints)
            );
        } else {
            assertEq(
                eulerEulerEarnVault.totalAllocationPoints(),
                totalAllocationPointsBefore + (_newAllocationPoints - strategyAllocationPoints)
            );
        }
        assertEq(_getWithdrawalQueueLength(), withdrawalQueueLengthBefore);
        assertEq(strategy.allocationPoints, _newAllocationPoints);
    }
}
