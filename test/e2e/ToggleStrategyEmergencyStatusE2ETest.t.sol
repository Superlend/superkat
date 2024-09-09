// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract ToggleStrategyEmergencyStatusE2ETest is YieldAggregatorBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 user2InitialBalance = 100000e18;

    IEVault eTSTsecondary;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        {
            eTSTsecondary = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );
            eTSTsecondary.setHookConfig(address(0), 0);
            eTSTsecondary.setInterestRateModel(address(new IRMTestDefault()));
            eTSTsecondary.setMaxLiquidationDiscount(0.2e4);
            eTSTsecondary.setFeeReceiver(feeReceiver);

            _addStrategy(manager, address(eTSTsecondary), 1000e18);
        }

        assetTST.mint(user1, user1InitialBalance);
        assetTST.mint(user2, user2InitialBalance);
    }

    function testToggleStrategyEmergencyStatus() public {
        uint256 totalAllocationPointsBefore = eulerYieldAggregatorVault.totalAllocationPoints();

        vm.prank(manager);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(eTSTsecondary));

        IYieldAggregator.Strategy memory strategyAfter = eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary));

        assertEq(strategyAfter.status == IYieldAggregator.StrategyStatus.Emergency, true);
        assertEq(
            eulerYieldAggregatorVault.totalAllocationPoints(),
            totalAllocationPointsBefore - strategyAfter.allocationPoints
        );

        totalAllocationPointsBefore = eulerYieldAggregatorVault.totalAllocationPoints();

        vm.prank(manager);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(eTSTsecondary));

        strategyAfter = eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary));
        assertEq(strategyAfter.status == IYieldAggregator.StrategyStatus.Active, true);
        assertEq(
            eulerYieldAggregatorVault.totalAllocationPoints(),
            totalAllocationPointsBefore + strategyAfter.allocationPoints
        );
    }

    function testToggleStrategyEmergencyStatusForInactiveStrategy() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(0x2));
        vm.stopPrank();
    }

    // this to test a scneraio where a strategy `withdraw()` start reverting.
    // Guardian will set the strategy in emergency mode, harvest and withdraw should execute,
    // user will be able to withdraw from other strategy, losses will only be in the faulty strategy.
    function testDepositRebalanceWithdrawWithFaultyStartegy() public {
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
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4k for reserve, 2k for eTST, 4k for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IYieldAggregator.Strategy memory eTSTstrategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
            IYieldAggregator.Strategy memory eTSTsecondarystrategyBefore =
                eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary));

            assertEq(
                eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), eTSTstrategyBefore.allocated
            );
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(
                eulerYieldAggregatorVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary))).allocated,
                expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerYieldAggregatorVault)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        // set eTST in emergency mode
        vm.prank(manager);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(eTST));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough, user should be able to withdraw
        {
            uint256 amountToWithdraw = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssets = eulerYieldAggregatorVault.convertToAssets(amountToWithdraw);

            uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToWithdraw);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToWithdraw, user1, user1);

            assertTrue(eTST.balanceOf(address(eulerYieldAggregatorVault)) != 0);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), 0);
            assertEq(eulerYieldAggregatorVault.totalSupply(), 0);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssets);
            assertEq(previewedAssets, withdrawnAssets);
        }
    }

    function testToggleCashReserveStrategyStatus() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.CanNotToggleStrategyEmergencyStatus.selector);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(0));
        vm.stopPrank();
    }

    function testRemoveStrategyInEmergencyStatus() public {
        vm.prank(manager);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(eTSTsecondary));

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerYieldAggregatorVault.removeStrategy(address(eTSTsecondary));
    }

    function testSetEmergencyAndReactive() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            vm.startPrank(user1);
            assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
            eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            vm.startPrank(user2);
            assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
            eulerYieldAggregatorVault.deposit(amountToDeposit, user2);
            vm.stopPrank();
        }
        assertEq(eulerYieldAggregatorVault.totalAllocated(), 0);

        // rebalance into strategy
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4k for reserve, 2k for eTST, 4k for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IYieldAggregator.Strategy memory eTSTstrategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
            IYieldAggregator.Strategy memory eTSTsecondarystrategyBefore =
                eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary));

            assertEq(
                eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), eTSTstrategyBefore.allocated
            );
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(
                eulerYieldAggregatorVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary))).allocated,
                expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerYieldAggregatorVault)),
                amountToDeposit * 2 - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        // set eTST in emergency mode
        uint256 totalAllocationBefore = eulerYieldAggregatorVault.totalAllocationPoints();
        vm.prank(manager);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(eTST));
        assertEq(
            eulerYieldAggregatorVault.totalAllocationPoints(),
            totalAllocationBefore - (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocationPoints
        );

        // // user 1 full withdraw, will have to withdraw from strategy as cash reserve is not enough, user should be able to withdraw
        {
            uint256 amountToWithdraw = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);
            uint256 expectedAssets = eulerYieldAggregatorVault.convertToAssets(amountToWithdraw);
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();

            assertTrue(totalAssetsDepositedBefore != 0);

            uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToWithdraw);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToWithdraw, user1, user1);

            assertTrue(eTST.balanceOf(address(eulerYieldAggregatorVault)) != 0);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets);
            assertEq(eulerYieldAggregatorVault.totalSupply(), eulerYieldAggregatorVault.balanceOf(user2));
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssets);
            assertEq(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore);
            assertEq(previewedAssets, withdrawnAssets);
        }

        vm.warp(block.timestamp + 86400);

        // re-activate eTST back again
        totalAllocationBefore = eulerYieldAggregatorVault.totalAllocationPoints();
        vm.prank(manager);
        eulerYieldAggregatorVault.toggleStrategyEmergencyStatus(address(eTST));
        assertEq(
            eulerYieldAggregatorVault.totalAllocationPoints(),
            totalAllocationBefore + (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocationPoints
        );

        eulerYieldAggregatorVault.gulp();

        // user 2 full withdraw
        {
            uint256 amountToWithdraw = eulerYieldAggregatorVault.balanceOf(user2);
            uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);
            uint256 expectedAssets = eulerYieldAggregatorVault.convertToAssets(amountToWithdraw);
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();

            assertTrue(totalAssetsDepositedBefore != 0);

            uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToWithdraw);
            vm.prank(user2);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToWithdraw, user2, user2);

            assertEq(eTST.balanceOf(address(eulerYieldAggregatorVault)), 0);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), 0);
            assertEq(eulerYieldAggregatorVault.totalSupply(), 0);
            assertEq(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore + expectedAssets);
            assertEq(previewedAssets, withdrawnAssets);
        }

        IYieldAggregator.Strategy memory eTSTsecondaryStrategy =
            eulerYieldAggregatorVault.getStrategy(address(eTSTsecondary));
        (,, uint168 interestLeft) = eulerYieldAggregatorVault.getYieldAggregatorSavingRate();

        assertEq(interestLeft, eTSTsecondaryStrategy.allocated);
    }
}
