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
    ErrorsLib,
    AggAmountCapLib,
    AggAmountCap
} from "../common/EulerAggregationVaultBase.t.sol";

contract StrategyCapE2ETest is EulerAggregationVaultBase {
    uint256 user1InitialBalance = 100000e18;

    using AggAmountCapLib for AggAmountCap;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSetCap() public {
        uint256 cap = 100e18;

        assertEq(AggAmountCap.unwrap(eulerAggregationVault.getStrategy(address(eTST)).cap), 0);

        vm.prank(manager);
        // 100e18 cap
        eulerAggregationVault.setStrategyCap(address(eTST), 6420);

        IEulerAggregationVault.Strategy memory strategy = eulerAggregationVault.getStrategy(address(eTST));

        assertEq(strategy.cap.resolve(), cap);
        assertEq(AggAmountCap.unwrap(strategy.cap), 6420);
    }

    function testSetCapForInactiveStrategy() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        eulerAggregationVault.setStrategyCap(address(0x2), 1);
    }

    function testSetCapForCashReserveStrategy() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.NoCapOnCashReserveStrategy.selector);
        eulerAggregationVault.setStrategyCap(address(0), 1);
    }

    function testRebalanceAfterHittingCap() public {
        address[] memory strategiesToRebalance = new address[](1);

        uint120 cappedBalance = 3000000000000000000000;
        // 3000000000000000000000 cap
        uint16 cap = 19221;
        vm.prank(manager);
        eulerAggregationVault.setStrategyCap(address(eTST), cap);
        IEulerAggregationVault.Strategy memory strategy = eulerAggregationVault.getStrategy(address(eTST));
        assertEq(strategy.cap.resolve(), cappedBalance);
        assertEq(AggAmountCap.unwrap(strategy.cap), cap);

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

            assertTrue(expectedStrategyCash > cappedBalance);
            assertEq(eulerAggregationVault.totalAllocated(), cappedBalance);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), cappedBalance);
            assertEq(
                (eulerAggregationVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + cappedBalance
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

            // set cap at around 10% less than target allocation
            uint16 cap = 19219;
            vm.prank(manager);
            eulerAggregationVault.setStrategyCap(address(eTST), cap);

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), AggAmountCap.wrap(cap).resolve());
            assertEq(
                eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), AggAmountCap.wrap(cap).resolve()
            );
            assertEq(
                (eulerAggregationVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + AggAmountCap.wrap(cap).resolve()
            );
        }
    }
}
