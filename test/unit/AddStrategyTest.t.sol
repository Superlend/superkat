// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    ErrorsLib,
    IEVault,
    IRMTestDefault
} from "../common/EulerAggregationVaultBase.t.sol";

contract AddStrategyTest is EulerAggregationVaultBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function testAddStrategy() public {
        uint256 allocationPoints = 500e18;
        uint256 totalAllocationPointsBefore = eulerAggregationVault.totalAllocationPoints();

        assertEq(_getWithdrawalQueueLength(), 0);

        _addStrategy(manager, address(eTST), allocationPoints);

        assertEq(eulerAggregationVault.totalAllocationPoints(), allocationPoints + totalAllocationPointsBefore);
        assertEq(_getWithdrawalQueueLength(), 1);
    }

    function testAddStrategy_FromUnauthorizedAddress() public {
        uint256 allocationPoints = 500e18;

        assertEq(_getWithdrawalQueueLength(), 0);

        vm.expectRevert();
        _addStrategy(deployer, address(eTST), allocationPoints);
    }

    function testAddStrategy_WithInvalidAsset() public {
        uint256 allocationPoints = 500e18;

        assertEq(_getWithdrawalQueueLength(), 0);

        vm.expectRevert(ErrorsLib.InvalidStrategyAsset.selector);
        _addStrategy(manager, address(eTST2), allocationPoints);
    }

    function testAddStrategy_AlreadyAddedStrategy() public {
        uint256 allocationPoints = 500e18;
        uint256 totalAllocationPointsBefore = eulerAggregationVault.totalAllocationPoints();

        assertEq(_getWithdrawalQueueLength(), 0);

        _addStrategy(manager, address(eTST), allocationPoints);

        assertEq(eulerAggregationVault.totalAllocationPoints(), allocationPoints + totalAllocationPointsBefore);
        assertEq(_getWithdrawalQueueLength(), 1);

        vm.expectRevert(ErrorsLib.StrategyAlreadyExist.selector);
        _addStrategy(manager, address(eTST), allocationPoints);
    }

    function testAddStrategy_WithInvalidPoints() public {
        uint256 allocationPoints = 0;

        vm.expectRevert(ErrorsLib.InvalidAllocationPoints.selector);
        _addStrategy(manager, address(eTST), allocationPoints);
    }

    function testAddStrategy_MaxStrategiesExceeded() public {
        IEVault[] memory strategies = new IEVault[](11);

        uint256 allocationPoints = 500e18;
        for (uint256 i; i < 10; i++) {
            strategies[i] = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );

            _addStrategy(manager, address(strategies[i]), allocationPoints);
        }

        strategies[10] = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        vm.expectRevert(ErrorsLib.MaxStrategiesExceeded.selector);
        _addStrategy(manager, address(strategies[10]), allocationPoints);
    }
}
