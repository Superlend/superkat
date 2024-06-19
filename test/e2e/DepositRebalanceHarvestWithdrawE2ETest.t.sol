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
    WithdrawalQueue,
    Strategy
} from "../common/AggregationLayerVaultBase.t.sol";

contract DepositRebalanceHarvestWithdrawE2ETest is AggregationLayerVaultBase {
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
            Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

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

        vm.warp(block.timestamp + 86400);
        // partial withdraw, no need to withdraw from strategy as cash reserve is enough
        uint256 amountToWithdraw = 6000e18;
        {
            Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));
            uint256 strategyShareBalanceBefore = eTST.balanceOf(address(aggregationLayerVault));
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            aggregationLayerVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(aggregationLayerVault)), strategyShareBalanceBefore);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        }

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            amountToWithdraw = amountToDeposit - amountToWithdraw;
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            aggregationLayerVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(aggregationLayerVault)), 0);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, 0);
        }
    }

    function testSingleStrategy_WithYield() public {
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
            Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);

            assertEq(aggregationLayerVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), expectedStrategyCash);
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(aggregationLayerVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = aggregationLayerVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            aggregationLayerVault.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(aggregationLayerVault)), yield);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + aggregationLayerVault.convertToAssets(amountToWithdraw)
            );
        }
    }

    function testMultipleStrategy_WithYield() public {
        IEVault eTSTsecondary;
        {
            eTSTsecondary = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );
            eTSTsecondary.setInterestRateModel(address(new IRMTestDefault()));
            eTSTsecondary.setMaxLiquidationDiscount(0.2e4);
            eTSTsecondary.setFeeReceiver(feeReceiver);

            uint256 initialStrategyAllocationPoints = 1000e18;
            _addStrategy(manager, address(eTSTsecondary), initialStrategyAllocationPoints);
        }

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
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            Strategy memory eTSTstrategyBefore = aggregationLayerVault.getStrategy(address(eTST));
            Strategy memory eTSTsecondarystrategyBefore = aggregationLayerVault.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(aggregationLayerVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);

            assertEq(
                aggregationLayerVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(aggregationLayerVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (aggregationLayerVault.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(aggregationLayerVault)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of aggregator balance due to yield
        uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
        uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrenteTSTsecondaryUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
        uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
        uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
        uint256 eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
        uint256 eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

        assetTST.mint(address(eTST), eTSTYield);
        assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
        eTST.skim(type(uint256).max, address(aggregationLayerVault));
        eTSTsecondary.skim(type(uint256).max, address(aggregationLayerVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = aggregationLayerVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            aggregationLayerVault.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(aggregationLayerVault)), 0);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + aggregationLayerVault.convertToAssets(amountToWithdraw)
            );
        }
    }

    function testSingleStrategy_WithYield_WithInterest() public {
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
            Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);

            assertEq(aggregationLayerVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), expectedStrategyCash);
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(aggregationLayerVault));

        // harvest
        vm.prank(user1);
        aggregationLayerVault.harvest(address(eTST));
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = aggregationLayerVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            aggregationLayerVault.redeem(amountToWithdraw, user1, user1);

            // all yield is distributed
            assertApproxEqAbs(eTST.balanceOf(address(aggregationLayerVault)), 0, 1);
            assertApproxEqAbs(
                aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw, 1
            );
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToDeposit + yield, 1);
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
            eTSTsecondary.setInterestRateModel(address(new IRMTestDefault()));
            eTSTsecondary.setMaxLiquidationDiscount(0.2e4);
            eTSTsecondary.setFeeReceiver(feeReceiver);

            uint256 initialStrategyAllocationPoints = 1000e18;
            _addStrategy(manager, address(eTSTsecondary), initialStrategyAllocationPoints);
        }

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
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            Strategy memory eTSTstrategyBefore = aggregationLayerVault.getStrategy(address(eTST));
            Strategy memory eTSTsecondarystrategyBefore = aggregationLayerVault.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(aggregationLayerVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);

            assertEq(
                aggregationLayerVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(aggregationLayerVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (aggregationLayerVault.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(aggregationLayerVault)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            // mock an increase of aggregator balance due to yield
            uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(aggregationLayerVault));
            uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
            uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(aggregationLayerVault));
            uint256 aggrCurrenteTSTsecondaryUnderlyingBalance =
                eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
            uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

            assetTST.mint(address(eTST), eTSTYield);
            assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
            eTST.skim(type(uint256).max, address(aggregationLayerVault));
            eTSTsecondary.skim(type(uint256).max, address(aggregationLayerVault));
        }

        // harvest
        address[] memory strategiesToHarvest = new address[](2);
        strategiesToHarvest[0] = address(eTST);
        strategiesToHarvest[1] = address(eTSTsecondary);
        vm.prank(user1);
        aggregationLayerVault.harvestMultipleStrategies(strategiesToHarvest);
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = aggregationLayerVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            aggregationLayerVault.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(eTST.balanceOf(address(aggregationLayerVault)), 0, 0);
            assertApproxEqAbs(
                aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw, 1
            );
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + amountToDeposit + eTSTYield + eTSTsecondaryYield,
                1
            );
        }
    }

    function testWithdraw_NotEnoughAssets() public {
        IEVault eTSTsecondary;
        {
            eTSTsecondary = IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            );
            eTSTsecondary.setInterestRateModel(address(new IRMTestDefault()));
            eTSTsecondary.setMaxLiquidationDiscount(0.2e4);
            eTSTsecondary.setFeeReceiver(feeReceiver);

            uint256 initialStrategyAllocationPoints = 1000e18;
            _addStrategy(manager, address(eTSTsecondary), initialStrategyAllocationPoints);
        }

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
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            Strategy memory eTSTstrategyBefore = aggregationLayerVault.getStrategy(address(eTST));
            Strategy memory eTSTsecondarystrategyBefore = aggregationLayerVault.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(aggregationLayerVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = aggregationLayerVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / aggregationLayerVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            rebalancer.executeRebalance(address(aggregationLayerVault), strategiesToRebalance);

            assertEq(
                aggregationLayerVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(aggregationLayerVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (aggregationLayerVault.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(aggregationLayerVault)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            // mock an increase of aggregator balance due to yield
            uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(aggregationLayerVault));
            uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
            uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(aggregationLayerVault));
            uint256 aggrCurrenteTSTsecondaryUnderlyingBalance =
                eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
            uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

            assetTST.mint(address(eTST), eTSTYield);
            assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
            eTST.skim(type(uint256).max, address(aggregationLayerVault));
            eTSTsecondary.skim(type(uint256).max, address(aggregationLayerVault));
        }

        // harvest
        address[] memory strategiesToHarvest = new address[](1);
        strategiesToHarvest[0] = address(eTST);
        vm.prank(user1);
        aggregationLayerVault.harvestMultipleStrategies(strategiesToHarvest);
        vm.warp(block.timestamp + 2 weeks);

        vm.prank(manager);
        aggregationLayerVault.removeStrategy(address(eTSTsecondary));

        {
            uint256 amountToWithdraw = aggregationLayerVault.balanceOf(user1);

            vm.prank(user1);
            vm.expectRevert(WithdrawalQueue.NotEnoughAssets.selector);
            aggregationLayerVault.redeem(amountToWithdraw, user1, user1);
        }
    }
}
