// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    FourSixTwoSixAggBase,
    FourSixTwoSixAgg,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20
} from "../common/FourSixTwoSixAggBase.t.sol";

contract StrategyCapE2ETest is FourSixTwoSixAggBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetCap() public {
        uint256 cap = 1000000e18;

        assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).cap, 0);

        vm.prank(manager);
        fourSixTwoSixAgg.setStrategyCap(address(eTST), cap);

        FourSixTwoSixAgg.Strategy memory strategy = fourSixTwoSixAgg.getStrategy(address(eTST));

        assertEq(strategy.cap, cap);
    }

    function testSetCapForInactiveStrategy() public {
        uint256 cap = 1000000e18;

        vm.prank(manager);
        vm.expectRevert(FourSixTwoSixAgg.InactiveStrategy.selector);
        fourSixTwoSixAgg.setStrategyCap(address(0x2), cap);
    }

    function testRebalanceAfterHittingCap() public {
        uint256 cap = 3333333333333333333333;
        vm.prank(manager);
        fourSixTwoSixAgg.setStrategyCap(address(eTST), cap);

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), strategyBefore.allocated);

            uint256 expectedStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable() * strategyBefore.allocationPoints
                / fourSixTwoSixAgg.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(fourSixTwoSixAgg), strategiesToRebalance);

            assertEq(fourSixTwoSixAgg.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), expectedStrategyCash);
            assertEq(
                (fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, strategyBefore.allocated + expectedStrategyCash
            );
        }

        // deposit and rebalance again, no rebalance should happen as strategy reached max cap
        vm.warp(block.timestamp + 86400);
        vm.startPrank(user1);

        assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
        fourSixTwoSixAgg.deposit(amountToDeposit, user1);

        uint256 strategyAllocatedBefore = (fourSixTwoSixAgg.getStrategy(address(eTST))).allocated;

        address[] memory strategiesToRebalance = new address[](1);
        strategiesToRebalance[0] = address(eTST);
        rebalancer.executeRebalance(address(fourSixTwoSixAgg), strategiesToRebalance);
        vm.stopPrank();

        assertEq(strategyAllocatedBefore, (fourSixTwoSixAgg.getStrategy(address(eTST))).allocated);
    }

    function testRebalanceWhentargetAllocationGreaterThanCap() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), strategyBefore.allocated);

            uint256 expectedStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable() * strategyBefore.allocationPoints
                / fourSixTwoSixAgg.totalAllocationPoints();

            // set cap 10% less than target allocation
            uint256 cap = expectedStrategyCash * 9e17 / 1e18;
            vm.prank(manager);
            fourSixTwoSixAgg.setStrategyCap(address(eTST), cap);

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(fourSixTwoSixAgg), strategiesToRebalance);

            assertEq(fourSixTwoSixAgg.totalAllocated(), cap);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), cap);
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, strategyBefore.allocated + cap);
        }
    }
}
