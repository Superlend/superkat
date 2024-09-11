// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract DepositRebalanceHarvestWithdrawE2ETest is YieldAggregatorBase {
    uint256 user1InitialBalance = 100000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);
    }

    function testSingleStrategy_NoYield() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(eulerYieldAggregatorVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedStrategyCash);
            assertEq(
                (eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }

        vm.warp(block.timestamp + 86400);
        // partial withdraw, no need to withdraw from strategy as cash reserve is enough
        uint256 amountToWithdraw = 6000e18;
        {
            IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
            uint256 strategyShareBalanceBefore = eTST.balanceOf(address(eulerYieldAggregatorVault));
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedShares = eulerYieldAggregatorVault.previewWithdraw(amountToWithdraw);
            vm.prank(user1);
            uint256 burnedShares = eulerYieldAggregatorVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerYieldAggregatorVault)), strategyShareBalanceBefore);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerYieldAggregatorVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);

            assertEq(burnedShares, previewedShares);
        }

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            amountToWithdraw = amountToDeposit - amountToWithdraw;
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedShares = eulerYieldAggregatorVault.previewWithdraw(amountToWithdraw);
            vm.prank(user1);
            uint256 burnedShares = eulerYieldAggregatorVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerYieldAggregatorVault)), 0);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerYieldAggregatorVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, 0);

            assertEq(previewedShares, burnedShares);
        }
    }

    function testSingleStrategy_WithYield() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(eulerYieldAggregatorVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedStrategyCash);
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerYieldAggregatorVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToRedeem, user1, user1);

            assertEq(eTST.balanceOf(address(eulerYieldAggregatorVault)), yield);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem);
            assertEq(eulerYieldAggregatorVault.totalSupply(), aggregatorTotalSupplyBefore - amountToRedeem);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerYieldAggregatorVault.convertToAssets(amountToRedeem)
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
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
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

        vm.warp(block.timestamp + 1.5 days);
        // mock an increase of aggregator balance due to yield
        uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
        uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrenteTSTsecondaryUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
        uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
        uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
        uint256 eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
        uint256 eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

        assetTST.mint(address(eTST), eTSTYield);
        assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
        eTST.skim(type(uint256).max, address(eulerYieldAggregatorVault));
        eTSTsecondary.skim(type(uint256).max, address(eulerYieldAggregatorVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToRedeem, user1, user1);

            assertEq(eTST.balanceOf(address(eulerYieldAggregatorVault)), 0);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem);
            assertEq(eulerYieldAggregatorVault.totalSupply(), aggregatorTotalSupplyBefore - amountToRedeem);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerYieldAggregatorVault.convertToAssets(amountToRedeem)
            );

            assertEq(previewedAssets, withdrawnAssets);
        }
    }

    function testSingleStrategy_WithYield_WithInterest() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(eulerYieldAggregatorVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedStrategyCash);
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerYieldAggregatorVault));

        // harvest
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToRedeem, user1, user1);

            // all yield is distributed
            assertApproxEqAbs(eTST.balanceOf(address(eulerYieldAggregatorVault)), 0, 1);
            assertApproxEqAbs(
                eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem, 1
            );
            assertEq(eulerYieldAggregatorVault.totalSupply(), aggregatorTotalSupplyBefore - amountToRedeem);
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
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
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

        vm.warp(block.timestamp + 86400);
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            // mock an increase of aggregator balance due to yield
            uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
            uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
            uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerYieldAggregatorVault));
            uint256 aggrCurrenteTSTsecondaryUnderlyingBalance =
                eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
            uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

            assetTST.mint(address(eTST), eTSTYield);
            assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
            eTST.skim(type(uint256).max, address(eulerYieldAggregatorVault));
            eTSTsecondary.skim(type(uint256).max, address(eulerYieldAggregatorVault));
        }

        // harvest
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToRedeem = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            uint256 maxAssets = eulerYieldAggregatorVault.maxWithdraw(user1);
            uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToRedeem);
            vm.prank(user1);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToRedeem, user1, user1);

            assertApproxEqAbs(eTST.balanceOf(address(eulerYieldAggregatorVault)), 0, 0);
            assertApproxEqAbs(
                eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToRedeem, 1
            );
            assertEq(eulerYieldAggregatorVault.totalSupply(), aggregatorTotalSupplyBefore - amountToRedeem);
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
            IYieldAggregator.Strategy memory eTSTstrategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

            assertEq(
                eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), eTSTstrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            vm.prank(user1);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(eulerYieldAggregatorVault.totalAllocated(), expectedeTSTStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedeTSTStrategyCash);
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(assetTST.balanceOf(address(eulerYieldAggregatorVault)), amountToDeposit - expectedeTSTStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // harvest
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        // mock decrease by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewWithdraw.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(eulerYieldAggregatorVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        uint256 amountToRedeem = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 previewedShares = eulerYieldAggregatorVault.previewWithdraw(amountToDeposit);
        assertEq(amountToRedeem, previewedShares);

        uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(amountToRedeem);
        uint256 maxAssets = eulerYieldAggregatorVault.maxWithdraw(user1);
        assertLt(maxAssets, previewedAssets);

        vm.prank(user1);
        vm.expectRevert(ErrorsLib.NotEnoughAssets.selector);
        eulerYieldAggregatorVault.redeem(amountToRedeem, user1, user1);

        vm.clearMockedCalls();
    }
}
