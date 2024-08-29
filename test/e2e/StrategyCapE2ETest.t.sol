// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    YieldAggregatorBase,
    YieldAggregator,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IYieldAggregator,
    ErrorsLib,
    AggAmountCapLib,
    AggAmountCap
} from "../common/YieldAggregatorBase.t.sol";

contract StrategyCapE2ETest is YieldAggregatorBase {
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

        assertEq(AggAmountCap.unwrap(eulerYieldAggregatorVault.getStrategy(address(eTST)).cap), 0);

        vm.prank(manager);
        // 100e18 cap
        eulerYieldAggregatorVault.setStrategyCap(address(eTST), 6420);

        IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(address(eTST));

        assertEq(strategy.cap.resolve(), cap);
        assertEq(AggAmountCap.unwrap(strategy.cap), 6420);
    }

    function testSetCapForInactiveStrategy() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerYieldAggregatorVault.setStrategyCap(address(0x2), 1);
    }

    function testSetCapForCashReserveStrategy() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.NoCapOnCashReserveStrategy.selector);
        eulerYieldAggregatorVault.setStrategyCap(address(0), 1);
    }

    function testRebalanceAfterHittingCap() public {
        address[] memory strategiesToRebalance = new address[](1);

        uint120 cappedBalance = 3000000000000000000000;
        // 3000000000000000000000 cap
        uint16 cap = 19221;
        vm.prank(manager);
        eulerYieldAggregatorVault.setStrategyCap(address(eTST), cap);
        IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(address(eTST));
        assertEq(strategy.cap.resolve(), cappedBalance);
        assertEq(AggAmountCap.unwrap(strategy.cap), cap);

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
            eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();

            vm.prank(user1);
            strategiesToRebalance[0] = address(eTST);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertTrue(expectedStrategyCash > cappedBalance);
            assertEq(eulerYieldAggregatorVault.totalAllocated(), cappedBalance);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), cappedBalance);
            assertEq(
                (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + cappedBalance
            );
        }

        // deposit and rebalance again, no rebalance should happen as strategy reached max cap
        vm.warp(block.timestamp + 86400);
        vm.startPrank(user1);

        assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
        eulerYieldAggregatorVault.deposit(amountToDeposit, user1);

        uint256 strategyAllocatedBefore = (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated;

        strategiesToRebalance[0] = address(eTST);
        eulerYieldAggregatorVault.rebalance(strategiesToRebalance);
        vm.stopPrank();

        assertEq(strategyAllocatedBefore, (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated);
    }

    function testRebalanceWhentargetAllocationGreaterThanCap() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
            eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

            // set cap at around 10% less than target allocation
            uint16 cap = 19219;
            vm.prank(manager);
            eulerYieldAggregatorVault.setStrategyCap(address(eTST), cap);

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(eulerYieldAggregatorVault.totalAllocated(), AggAmountCap.wrap(cap).resolve());
            assertEq(
                eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))),
                AggAmountCap.wrap(cap).resolve()
            );
            assertEq(
                (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + AggAmountCap.wrap(cap).resolve()
            );
        }
    }
}
