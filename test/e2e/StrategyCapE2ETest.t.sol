// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationVault,
    ErrorsLib
} from "../common/EulerAggregationVaultBase.t.sol";

contract StrategyCapE2ETest is EulerAggregationVaultBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetCap() public {
        uint256 cap = 1000000e18;

        assertEq((eulerAggregationVault.getStrategy(address(eTST))).cap, 0);

        vm.prank(manager);
        eulerAggregationVault.setStrategyCap(address(eTST), cap);

        IEulerAggregationVault.Strategy memory strategy = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(strategy.cap, cap);
    }

    function testSetCapForInactiveStrategy() public {
        uint256 cap = 1000000e18;

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        eulerAggregationVault.setStrategyCap(address(0x2), cap);
    }

    function testSetCapForCashReserveStrategy() public {
        uint256 cap = 1000000e18;

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.NoCapOnCashReserveStrategy.selector);
        eulerAggregationVault.setStrategyCap(address(0), cap);
    }

    function testRebalanceAfterHittingCap() public {
        address[] memory strategiesToRebalance = new address[](1);

        uint256 cap = 3333333333333333333333;
        vm.prank(manager);
        eulerAggregationVault.setStrategyCap(address(eTST), cap);

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationVault), amountToDeposit);
            eulerAggregationVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();

            vm.prank(user1);
            strategiesToRebalance[0] = address(eTST);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq(
                (eulerAggregationVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }

        // deposit and rebalance again, no rebalance should happen as strategy reached max cap
        vm.warp(block.timestamp + 86400);
        vm.startPrank(user1);

        assetTST.approve(address(eulerAggregationVault), amountToDeposit);
        eulerAggregationVault.deposit(amountToDeposit, user1);

        uint256 strategyAllocatedBefore = (eulerAggregationVault.getStrategy(address(eTST))).allocated;

        strategiesToRebalance[0] = address(eTST);
        eulerAggregationVault.rebalance(strategiesToRebalance);
        vm.stopPrank();

        assertEq(strategyAllocatedBefore, (eulerAggregationVault.getStrategy(address(eTST))).allocated);
    }

    function testRebalanceWhentargetAllocationGreaterThanCap() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationVault), amountToDeposit);
            eulerAggregationVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();

            // set cap 10% less than target allocation
            uint256 cap = expectedStrategyCash * 9e17 / 1e18;
            vm.prank(manager);
            eulerAggregationVault.setStrategyCap(address(eTST), cap);

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), cap);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), cap);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + cap);
        }
    }
}
