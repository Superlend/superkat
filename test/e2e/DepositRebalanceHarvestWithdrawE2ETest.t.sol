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
    WithdrawalQueue,
    IEulerAggregationVault,
    ErrorsLib
} from "../common/EulerAggregationVaultBase.t.sol";

contract DepositRebalanceHarvestWithdrawE2ETest is EulerAggregationVaultBase {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq(
                (eulerAggregationVault.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }

        vm.warp(block.timestamp + 86400);
        // partial withdraw, no need to withdraw from strategy as cash reserve is enough
        uint256 amountToWithdraw = 6000e18;
        {
            IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
            uint256 strategyShareBalanceBefore = eTST.balanceOf(address(eulerAggregationVault));
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationVault)), strategyShareBalanceBefore);
            assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        }

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            amountToWithdraw = amountToDeposit - amountToWithdraw;
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationVault.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationVault)), 0);
            assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, 0);
        }
    }

    function testSingleStrategy_WithYield() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerAggregationVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationVault.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationVault)), yield);
            assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerAggregationVault.convertToAssets(amountToWithdraw)
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
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationVault.Strategy memory eTSTstrategyBefore = eulerAggregationVault.getStrategy(address(eTST));
            IEulerAggregationVault.Strategy memory eTSTsecondarystrategyBefore =
                eulerAggregationVault.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(
                eulerAggregationVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerAggregationVault.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerAggregationVault)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of aggregator balance due to yield
        uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
        uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrenteTSTsecondaryUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
        uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
        uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
        uint256 eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
        uint256 eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

        assetTST.mint(address(eTST), eTSTYield);
        assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
        eTST.skim(type(uint256).max, address(eulerAggregationVault));
        eTSTsecondary.skim(type(uint256).max, address(eulerAggregationVault));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationVault.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationVault)), 0);
            assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerAggregationVault.convertToAssets(amountToWithdraw)
            );
        }
    }

    function testSingleStrategy_WithYield_WithInterest() public {
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
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerAggregationVault));

        // harvest
        vm.prank(user1);
        eulerAggregationVault.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationVault.redeem(amountToWithdraw, user1, user1);

            // all yield is distributed
            assertApproxEqAbs(eTST.balanceOf(address(eulerAggregationVault)), 0, 1);
            assertApproxEqAbs(
                eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw, 1
            );
            assertEq(eulerAggregationVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
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
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationVault.Strategy memory eTSTstrategyBefore = eulerAggregationVault.getStrategy(address(eTST));
            IEulerAggregationVault.Strategy memory eTSTsecondarystrategyBefore =
                eulerAggregationVault.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationVault))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(
                eulerAggregationVault.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationVault))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerAggregationVault.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerAggregationVault)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            // mock an increase of aggregator balance due to yield
            uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(eulerAggregationVault));
            uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
            uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerAggregationVault));
            uint256 aggrCurrenteTSTsecondaryUnderlyingBalance =
                eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
            uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

            assetTST.mint(address(eTST), eTSTYield);
            assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
            eTST.skim(type(uint256).max, address(eulerAggregationVault));
            eTSTsecondary.skim(type(uint256).max, address(eulerAggregationVault));
        }

        // harvest
        vm.prank(user1);
        eulerAggregationVault.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationVault.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(eTST.balanceOf(address(eulerAggregationVault)), 0, 0);
            assertApproxEqAbs(
                eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw, 1
            );
            assertEq(eulerAggregationVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + amountToDeposit + eTSTYield + eTSTsecondaryYield,
                1
            );
        }
    }

    function testWithdraw_NotEnoughAssets() public {
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
            IEulerAggregationVault.Strategy memory eTSTstrategyBefore = eulerAggregationVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), eTSTstrategyBefore.allocated);

            uint256 expectedeTSTStrategyCash = eulerAggregationVault.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerAggregationVault.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            vm.prank(user1);
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedeTSTStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedeTSTStrategyCash);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(assetTST.balanceOf(address(eulerAggregationVault)), amountToDeposit - expectedeTSTStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // harvest
        vm.prank(user1);
        eulerAggregationVault.harvest();

        // mock decrease by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(eulerAggregationVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        uint256 amountToRedeem = eulerAggregationVault.balanceOf(user1);
        vm.prank(user1);
        vm.expectRevert(ErrorsLib.NotEnoughAssets.selector);
        eulerAggregationVault.redeem(amountToRedeem, user1, user1);

        vm.clearMockedCalls();
    }
}
