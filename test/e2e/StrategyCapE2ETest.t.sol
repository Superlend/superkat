// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationLayer,
    ErrorsLib
} from "../common/EulerAggregationLayerBase.t.sol";

contract StrategyCapE2ETest is EulerAggregationLayerBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetCap() public {
        uint256 cap = 1000000e18;

        assertEq((eulerAggregationLayer.getStrategy(address(eTST))).cap, 0);

        vm.prank(manager);
        eulerAggregationLayer.setStrategyCap(address(eTST), cap);

        IEulerAggregationLayer.Strategy memory strategy = eulerAggregationLayer.getStrategy(address(eTST));

        assertEq(strategy.cap, cap);
    }

    function testSetCapForInactiveStrategy() public {
        uint256 cap = 1000000e18;

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        eulerAggregationLayer.setStrategyCap(address(0x2), cap);
    }

    function testRebalanceAfterHittingCap() public {
        address[] memory strategiesToRebalance = new address[](1);

        uint256 cap = 3333333333333333333333;
        vm.prank(manager);
        eulerAggregationLayer.setStrategyCap(address(eTST), cap);

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            vm.prank(user1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(eulerAggregationLayer.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedStrategyCash);
            assertEq(
                (eulerAggregationLayer.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }

        // deposit and rebalance again, no rebalance should happen as strategy reached max cap
        vm.warp(block.timestamp + 86400);
        vm.startPrank(user1);

        assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
        eulerAggregationLayer.deposit(amountToDeposit, user1);

        uint256 strategyAllocatedBefore = (eulerAggregationLayer.getStrategy(address(eTST))).allocated;

        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);
        vm.stopPrank();

        assertEq(strategyAllocatedBefore, (eulerAggregationLayer.getStrategy(address(eTST))).allocated);
    }

    function testRebalanceWhentargetAllocationGreaterThanCap() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            // set cap 10% less than target allocation
            uint256 cap = expectedStrategyCash * 9e17 / 1e18;
            vm.prank(manager);
            eulerAggregationLayer.setStrategyCap(address(eTST), cap);

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(eulerAggregationLayer.totalAllocated(), cap);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), cap);
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, strategyBefore.allocated + cap);
        }
    }
}
