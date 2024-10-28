// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract ToggleStrategyEmergencyStatusE2ETest is EulerEarnBase {
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
        uint256 totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();

        vm.prank(manager);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(eTSTsecondary));

        IEulerEarn.Strategy memory strategyAfter = eulerEulerEarnVault.getStrategy(address(eTSTsecondary));

        assertEq(strategyAfter.status == IEulerEarn.StrategyStatus.Emergency, true);
        assertEq(
            eulerEulerEarnVault.totalAllocationPoints(), totalAllocationPointsBefore - strategyAfter.allocationPoints
        );

        totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();

        vm.prank(manager);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(eTSTsecondary));

        strategyAfter = eulerEulerEarnVault.getStrategy(address(eTSTsecondary));
        assertEq(strategyAfter.status == IEulerEarn.StrategyStatus.Active, true);
        assertEq(
            eulerEulerEarnVault.totalAllocationPoints(), totalAllocationPointsBefore + strategyAfter.allocationPoints
        );
    }

    function testToggleStrategyEmergencyStatusForInactiveStrategy() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.InactiveStrategy.selector);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(0x2));
        vm.stopPrank();
    }

    // this to test a scneraio where a strategy `withdraw()` start reverting.
    // Guardian will set the strategy in emergency mode, harvest and withdraw should execute,
    // user will be able to withdraw from other strategy, losses will only be in the faulty strategy.
    function testDepositRebalanceWithdrawWithFaultyStartegy() public {
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
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4k for reserve, 2k for eTST, 4k for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerEarn.Strategy memory eTSTstrategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
            IEulerEarn.Strategy memory eTSTsecondarystrategyBefore =
                eulerEulerEarnVault.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerEulerEarnVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(manager);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerEulerEarnVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerEulerEarnVault.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerEulerEarnVault)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        // set eTST in emergency mode
        vm.prank(manager);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(eTST));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough, user should be able to withdraw
        {
            uint256 amountToWithdraw = eulerEulerEarnVault.balanceOf(user1);
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssets = eulerEulerEarnVault.convertToAssets(amountToWithdraw);

            uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToWithdraw);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToWithdraw, user1, user1);

            assertTrue(eTST.balanceOf(address(eulerEulerEarnVault)) != 0);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), 0);
            assertEq(eulerEulerEarnVault.totalSupply(), 0);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssets);
            assertEq(previewedAssets, withdrawnAssets);
        }
    }

    function testToggleCashReserveStrategyStatus() public {
        vm.startPrank(manager);
        vm.expectRevert(ErrorsLib.CanNotToggleStrategyEmergencyStatus.selector);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(0));
        vm.stopPrank();
    }

    function testRemoveStrategyInEmergencyStatus() public {
        vm.prank(manager);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(eTSTsecondary));

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerEulerEarnVault.removeStrategy(address(eTSTsecondary));
    }

    function testSetEmergencyAndReactive() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into EulerEarn
        {
            vm.startPrank(user1);
            assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
            eulerEulerEarnVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            vm.startPrank(user2);
            assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
            eulerEulerEarnVault.deposit(amountToDeposit, user2);
            vm.stopPrank();
        }
        assertEq(eulerEulerEarnVault.totalAllocated(), 0);

        // rebalance into strategy
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4k for reserve, 2k for eTST, 4k for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerEarn.Strategy memory eTSTstrategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
            IEulerEarn.Strategy memory eTSTsecondarystrategyBefore =
                eulerEulerEarnVault.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerEulerEarnVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(manager);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerEulerEarnVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerEulerEarnVault.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerEulerEarnVault)),
                amountToDeposit * 2 - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        // set eTST in emergency mode
        uint256 totalAllocationBefore = eulerEulerEarnVault.totalAllocationPoints();
        vm.prank(manager);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(eTST));
        assertEq(
            eulerEulerEarnVault.totalAllocationPoints(),
            totalAllocationBefore - (eulerEulerEarnVault.getStrategy(address(eTST))).allocationPoints
        );

        // // user 1 full withdraw, will have to withdraw from strategy as cash reserve is not enough, user should be able to withdraw
        {
            uint256 amountToWithdraw = eulerEulerEarnVault.balanceOf(user1);
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);
            uint256 expectedAssets = eulerEulerEarnVault.convertToAssets(amountToWithdraw);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();

            assertTrue(totalAssetsDepositedBefore != 0);

            uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToWithdraw);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToWithdraw, user1, user1);

            assertTrue(eTST.balanceOf(address(eulerEulerEarnVault)) != 0);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets);
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEulerEarnVault.balanceOf(user2));
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssets);
            assertEq(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore);
            assertEq(previewedAssets, withdrawnAssets);
        }

        vm.warp(block.timestamp + 86400);

        // re-activate eTST back again
        totalAllocationBefore = eulerEulerEarnVault.totalAllocationPoints();
        vm.prank(manager);
        eulerEulerEarnVault.toggleStrategyEmergencyStatus(address(eTST));
        assertEq(
            eulerEulerEarnVault.totalAllocationPoints(),
            totalAllocationBefore + (eulerEulerEarnVault.getStrategy(address(eTST))).allocationPoints
        );

        eulerEulerEarnVault.gulp();

        // user 2 full withdraw
        {
            uint256 amountToWithdraw = eulerEulerEarnVault.balanceOf(user2);
            uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);
            uint256 expectedAssets = eulerEulerEarnVault.convertToAssets(amountToWithdraw);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();

            assertTrue(totalAssetsDepositedBefore != 0);

            uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToWithdraw);
            vm.prank(user2);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToWithdraw, user2, user2);

            assertEq(eTST.balanceOf(address(eulerEulerEarnVault)), 0);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), 0);
            assertEq(eulerEulerEarnVault.totalSupply(), 0);
            assertEq(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore + expectedAssets);
            assertEq(previewedAssets, withdrawnAssets);
        }

        IEulerEarn.Strategy memory eTSTsecondaryStrategy = eulerEulerEarnVault.getStrategy(address(eTSTsecondary));
        (,, uint168 interestLeft) = eulerEulerEarnVault.getEulerEarnSavingRate();

        assertEq(interestLeft, eTSTsecondaryStrategy.allocated);
    }
}
