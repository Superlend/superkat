// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IAggregationLayerVault,
    ErrorsLib
} from "../common/AggregationLayerVaultBase.t.sol";

contract StrategyCapE2ETest is AggregationLayerVaultBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetCap() public {
        uint256 cap = 1000000e18;

        assertEq((aggregationLayerVault.getStrategy(address(eTST))).cap, 0);

        vm.prank(manager);
        aggregationLayerVault.setStrategyCap(address(eTST), cap);

        IAggregationLayerVault.Strategy memory strategy = aggregationLayerVault.getStrategy(address(eTST));

        assertEq(strategy.cap, cap);
    }

    function testSetCapForInactiveStrategy() public {
        uint256 cap = 1000000e18;

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        aggregationLayerVault.setStrategyCap(address(0x2), cap);
    }

    function testRebalanceAfterHittingCap() public {
        uint256 cap = 3333333333333333333333;
        vm.prank(manager);
        aggregationLayerVault.setStrategyCap(address(eTST), cap);

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = aggregationLayerVault.balanceOf(user1);
            uint256 totalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(aggregationLayerVault), amountToDeposit);
            aggregationLayerVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(aggregationLayerVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(aggregationLayerVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);

            assertEq(aggregationLayerVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), expectedStrategyCash);
            assertEq(
                (aggregationLayerVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }

        // deposit and rebalance again, no rebalance should happen as strategy reached max cap
        vm.warp(block.timestamp + 86400);
        vm.startPrank(user1);

        assetTST.approve(address(aggregationLayerVault), amountToDeposit);
        aggregationLayerVault.deposit(amountToDeposit, user1);

        uint256 strategyAllocatedBefore = (aggregationLayerVault.getStrategy(address(eTST))).allocated;

        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);
        vm.stopPrank();

        assertEq(strategyAllocatedBefore, (aggregationLayerVault.getStrategy(address(eTST))).allocated);
    }

    function testRebalanceWhentargetAllocationGreaterThanCap() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = aggregationLayerVault.balanceOf(user1);
            uint256 totalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(aggregationLayerVault), amountToDeposit);
            aggregationLayerVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(aggregationLayerVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(aggregationLayerVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();

            // set cap 10% less than target allocation
            uint256 cap = expectedStrategyCash * 9e17 / 1e18;
            vm.prank(manager);
            aggregationLayerVault.setStrategyCap(address(eTST), cap);

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);

            assertEq(aggregationLayerVault.totalAllocated(), cap);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), cap);
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + cap);
        }
    }
}
