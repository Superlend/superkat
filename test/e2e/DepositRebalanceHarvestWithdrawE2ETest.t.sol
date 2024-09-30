// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract DepositRebalanceHarvestWithdrawE2ETest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(eulerEulerEarnVault.balanceTrackerAddress(), address(0));
    }

    function testSingleStrategy_NoYield() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
            assertEq(
                (eulerEulerEarnVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }

        vm.warp(block.timestamp + 86400);
        // partial withdraw, no need to withdraw from strategy as cash reserve is enough
        uint256 amountToWithdraw = 6000e18;
        {
            IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
            uint256 strategyShareBalanceBefore = eTST.balanceOf(address(eulerEulerEarnVault));
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedShares = eulerEulerEarnVault.previewWithdraw(amountToWithdraw);
            vm.prank(user1);
            uint256 burnedShares = eulerEulerEarnVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerEulerEarnVault)), strategyShareBalanceBefore);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);

            assertEq(burnedShares, previewedShares);
        }

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            amountToWithdraw = amountToDeposit - amountToWithdraw;
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedShares = eulerEulerEarnVault.previewWithdraw(amountToWithdraw);
            vm.prank(user1);
            uint256 burnedShares = eulerEulerEarnVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerEulerEarnVault)), 0);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, 0);

            assertEq(previewedShares, burnedShares);
        }
    }

    function testSingleStrategy_WithYield() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 earnCurrentStrategyShareBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        uint256 earnCurrentStrategyUnderlyingBalance = eTST.convertToAssets(earnCurrentStrategyShareBalance);
        uint256 earnNewStrategyUnderlyingBalance = earnCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = earnNewStrategyUnderlyingBalance - earnCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerEulerEarnVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToRedeem, user1, user1);

            assertEq(eTST.balanceOf(address(eulerEulerEarnVault)), yield);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem);
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToRedeem);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerEulerEarnVault.convertToAssets(amountToRedeem)
            );

            assertEq(previewedAssets, withdrawnAssets);
        }
    }

    function testHarvestMultipleStrategy_WithYield() public {
        IEVault eTSTsecondary;
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

            uint256 initialStrategyAllocationPoints = 1000e18;
            _addStrategy(manager, address(eTSTsecondary), initialStrategyAllocationPoints);
        }

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
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
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
            vm.prank(user1);
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

        vm.warp(block.timestamp + 1 days);
        // mock an increase of EulerEarn balance due to yield
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            uint256 earnCurrenteTSTShareBalance = eTST.balanceOf(address(eulerEulerEarnVault));
            uint256 earnCurrenteTSTUnderlyingBalance = eTST.convertToAssets(earnCurrenteTSTShareBalance);
            uint256 earnCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerEulerEarnVault));
            uint256 earnCurrenteTSTsecondaryUnderlyingBalance =
                eTSTsecondary.convertToAssets(earnCurrenteTSTsecondaryShareBalance);
            uint256 earnNeweTSTUnderlyingBalance = earnCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 earnNeweTSTsecondaryUnderlyingBalance = earnCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = earnNeweTSTUnderlyingBalance - earnCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = earnNeweTSTsecondaryUnderlyingBalance - earnCurrenteTSTsecondaryUnderlyingBalance;
        }

        assetTST.mint(address(eTST), eTSTYield);
        assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
        eTST.skim(type(uint256).max, address(eulerEulerEarnVault));
        eTSTsecondary.skim(type(uint256).max, address(eulerEulerEarnVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToRedeem, user1, user1);

            assertEq(eTST.balanceOf(address(eulerEulerEarnVault)), 0);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem);
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToRedeem);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerEulerEarnVault.convertToAssets(amountToRedeem)
            );

            assertEq(previewedAssets, withdrawnAssets);
        }
    }

    function testSingleStrategy_WithYield_WithInterest() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 earnCurrentStrategyShareBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        uint256 earnCurrentStrategyUnderlyingBalance = eTST.convertToAssets(earnCurrentStrategyShareBalance);
        uint256 earnNewStrategyUnderlyingBalance = earnCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = earnNewStrategyUnderlyingBalance - earnCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerEulerEarnVault));

        // harvest
        vm.prank(user1);
        eulerEulerEarnVault.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToRedeem, user1, user1);

            // all yield is distributed
            assertApproxEqAbs(eTST.balanceOf(address(eulerEulerEarnVault)), 0, 1);
            assertApproxEqAbs(
                eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem, 1
            );
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToRedeem);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToDeposit + yield, 1);

            assertEq(previewedAssets, withdrawnAssets);
        }
    }

    function testMultipleStrategy_WithYield_WithInterest() public {
        IEVault eTSTsecondary;
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

            uint256 initialStrategyAllocationPoints = 1000e18;
            _addStrategy(manager, address(eTSTsecondary), initialStrategyAllocationPoints);
        }

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
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
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
            vm.prank(user1);
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

        vm.warp(block.timestamp + 86400);
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            // mock an increase of EulerEarn balance due to yield
            uint256 earnCurrenteTSTShareBalance = eTST.balanceOf(address(eulerEulerEarnVault));
            uint256 earnCurrenteTSTUnderlyingBalance = eTST.convertToAssets(earnCurrenteTSTShareBalance);
            uint256 earnCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerEulerEarnVault));
            uint256 earnCurrenteTSTsecondaryUnderlyingBalance =
                eTSTsecondary.convertToAssets(earnCurrenteTSTsecondaryShareBalance);
            uint256 earnNeweTSTUnderlyingBalance = earnCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 earnNeweTSTsecondaryUnderlyingBalance = earnCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = earnNeweTSTUnderlyingBalance - earnCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = earnNeweTSTsecondaryUnderlyingBalance - earnCurrenteTSTsecondaryUnderlyingBalance;

            assetTST.mint(address(eTST), eTSTYield);
            assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
            eTST.skim(type(uint256).max, address(eulerEulerEarnVault));
            eTSTsecondary.skim(type(uint256).max, address(eulerEulerEarnVault));
        }

        // harvest
        vm.prank(user1);
        eulerEulerEarnVault.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 maxAssets = eulerEulerEarnVault.maxWithdraw(user1);
            uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToRedeem, user1, user1);

            assertApproxEqAbs(eTST.balanceOf(address(eulerEulerEarnVault)), 0, 0);
            assertApproxEqAbs(
                eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem, 1
            );
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToRedeem);
            assertApproxEqAbs(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + amountToDeposit + eTSTYield + eTSTsecondaryYield,
                1
            );

            assertEq(previewedAssets, withdrawnAssets);
            assertEq(maxAssets, withdrawnAssets);
        }
    }

    function testWithdraw_NotEnoughAssets() public {
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
            IEulerEarn.Strategy memory eTSTstrategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), eTSTstrategyBefore.allocated);

            uint256 expectedeTSTStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            vm.prank(user1);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedeTSTStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedeTSTStrategyCash);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(assetTST.balanceOf(address(eulerEulerEarnVault)), amountToDeposit - expectedeTSTStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // harvest
        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        // mock decrease by 10%
        uint256 earnCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        uint256 earnCurrentStrategyBalanceAfterNegYield = earnCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewWithdraw.selector, earnCurrentStrategyBalance),
            abi.encode(earnCurrentStrategyBalanceAfterNegYield)
        );
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(eulerEulerEarnVault)),
            abi.encode(earnCurrentStrategyBalanceAfterNegYield)
        );

        uint256 amountToRedeem = eulerEulerEarnVault.balanceOf(user1);
        uint256 previewedShares = eulerEulerEarnVault.previewWithdraw(amountToDeposit);
        assertEq(amountToRedeem, previewedShares);

        uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(amountToRedeem);
        uint256 maxAssets = eulerEulerEarnVault.maxWithdraw(user1);
        assertLt(maxAssets, previewedAssets);

        vm.prank(user1);
        vm.expectRevert(ErrorsLib.NotEnoughAssets.selector);
        eulerEulerEarnVault.redeem(amountToRedeem, user1, user1);

        vm.clearMockedCalls();
    }
}
