// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract StrategyCapE2ETest is EulerEarnBase {
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

        assertEq(AggAmountCap.unwrap(eulerEulerEarnVault.getStrategy(address(eTST)).cap), 0);

        vm.prank(manager);
        // 100e18 cap
        eulerEulerEarnVault.setStrategyCap(address(eTST), 6420);

        IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(address(eTST));

        assertEq(strategy.cap.resolve(), cap);
        assertEq(AggAmountCap.unwrap(strategy.cap), 6420);
    }

    function testSetCapForInactiveStrategy() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerEulerEarnVault.setStrategyCap(address(0x2), 1);
    }

    function testSetCapForCashReserveStrategy() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.NoCapOnCashReserveStrategy.selector);
        eulerEulerEarnVault.setStrategyCap(address(0), 1);
    }

    function testSetCapExceedingMax() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyCapExceedMax.selector);
        eulerEulerEarnVault.setStrategyCap(address(eTST), 51238);
    }

    function testRebalanceAfterHittingCap() public {
        address[] memory strategiesToRebalance = new address[](1);

        uint120 cappedBalance = 3000000000000000000000;
        // 3000000000000000000000 cap
        uint16 cap = 19221;
        vm.prank(manager);
        eulerEulerEarnVault.setStrategyCap(address(eTST), cap);
        IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(address(eTST));
        assertEq(strategy.cap.resolve(), cappedBalance);
        assertEq(AggAmountCap.unwrap(strategy.cap), cap);

        uint256 amountToDeposit = 10000e18;

        // deposit into EulerEarn
        {
            uint256 balanceBefore = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
            eulerEulerEarnVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerEulerEarnVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();

            vm.prank(user1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertTrue(expectedStrategyCash > cappedBalance);
            assertEq(eulerEulerEarnVault.totalAllocated(), cappedBalance);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), cappedBalance);
            assertEq(
                (eulerEulerEarnVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated + cappedBalance
            );
        }

        // deposit and rebalance again, no rebalance should happen as strategy reached max cap
        vm.warp(block.timestamp + 86400);
        vm.startPrank(user1);

        assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
        eulerEulerEarnVault.deposit(amountToDeposit, user1);

        uint256 strategyAllocatedBefore = (eulerEulerEarnVault.getStrategy(address(eTST))).allocated;

        strategiesToRebalance[0] = address(eTST);
        eulerEulerEarnVault.rebalance(strategiesToRebalance);
        vm.stopPrank();

        assertEq(strategyAllocatedBefore, (eulerEulerEarnVault.getStrategy(address(eTST))).allocated);
    }

    function testRebalanceWhentargetAllocationGreaterThanCap() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into EulerEarn
        {
            uint256 balanceBefore = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
            eulerEulerEarnVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerEulerEarnVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

            // set cap at around 10% less than target allocation
            uint16 cap = 19219;
            vm.prank(manager);
            eulerEulerEarnVault.setStrategyCap(address(eTST), cap);

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), AggAmountCap.wrap(cap).resolve());
            assertEq(
                eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), AggAmountCap.wrap(cap).resolve()
            );
            assertEq(
                (eulerEulerEarnVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + AggAmountCap.wrap(cap).resolve()
            );
        }
    }
}
