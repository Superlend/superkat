// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {console2} from "forge-std/console2.sol";
import {FourSixTwoSixAggBase, FourSixTwoSixAgg, IEVault} from "../common/FourSixTwoSixAggBase.t.sol";

contract RemoveStrategyTest is FourSixTwoSixAggBase {
    uint256 strategyAllocationPoints;

    IEVault anotherStrategy;

    function setUp() public virtual override {
        super.setUp();

        strategyAllocationPoints = 1000e18;
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

    function testRemoveStrategyWithMultipleStrategies() public {
        anotherStrategy = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        _addStrategy(manager, address(anotherStrategy), strategyAllocationPoints);

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

    function testRemoveStrategy_WithdrawalQueueOrdering() public {
        address strategy1 =
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount));
        address strategy2 =
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount));
        address strategy3 =
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount));

        _addStrategy(manager, strategy1, strategyAllocationPoints);
        _addStrategy(manager, strategy2, strategyAllocationPoints);
        _addStrategy(manager, strategy3, strategyAllocationPoints);

        address[] memory withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 4);
        assertEq(withdrawalQueue[0], address(eTST));
        assertEq(withdrawalQueue[1], strategy1);
        assertEq(withdrawalQueue[2], strategy2);
        assertEq(withdrawalQueue[3], strategy3);

        vm.prank(manager);
        fourSixTwoSixAgg.removeStrategy(strategy2);

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 3);
        assertEq(withdrawalQueue[0], address(eTST));
        assertEq(withdrawalQueue[1], strategy1);
        assertEq(withdrawalQueue[2], strategy3);

        vm.prank(manager);
        fourSixTwoSixAgg.removeStrategy(strategy3);

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 2);
        assertEq(withdrawalQueue[0], address(eTST));
        assertEq(withdrawalQueue[1], strategy1);

        vm.prank(manager);
        fourSixTwoSixAgg.removeStrategy(address(eTST));

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 1);
        assertEq(withdrawalQueue[0], strategy1);

        vm.prank(manager);
        fourSixTwoSixAgg.removeStrategy(strategy1);

        withdrawalQueue = _getWithdrawalQueue();
        assertEq(withdrawalQueue.length, 0);
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
