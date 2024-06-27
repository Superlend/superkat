// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    WithdrawalQueue,
    IEulerAggregationLayer
} from "../common/EulerAggregationLayerBase.t.sol";

contract DepositRebalanceHarvestWithdrawE2ETest is EulerAggregationLayerBase {
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
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(eulerAggregationLayer.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedStrategyCash);
            assertEq(
                (eulerAggregationLayer.getStrategy(address(eTST))).allocated,
                strategyBefore.allocated + expectedStrategyCash
            );
        }

        vm.warp(block.timestamp + 86400);
        // partial withdraw, no need to withdraw from strategy as cash reserve is enough
        uint256 amountToWithdraw = 6000e18;
        {
            IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));
            uint256 strategyShareBalanceBefore = eTST.balanceOf(address(eulerAggregationLayer));
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationLayer.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationLayer)), strategyShareBalanceBefore);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        }

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            amountToWithdraw = amountToDeposit - amountToWithdraw;
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationLayer.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationLayer)), 0);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, 0);
        }
    }

    function testSingleStrategy_WithYield() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(eulerAggregationLayer.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedStrategyCash);
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerAggregationLayer));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationLayer.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationLayer.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationLayer)), yield);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerAggregationLayer.convertToAssets(amountToWithdraw)
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
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory eTSTstrategyBefore = eulerAggregationLayer.getStrategy(address(eTST));
            IEulerAggregationLayer.Strategy memory eTSTsecondarystrategyBefore =
                eulerAggregationLayer.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(
                eulerAggregationLayer.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerAggregationLayer.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerAggregationLayer)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of aggregator balance due to yield
        uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
        uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
        uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerAggregationLayer));
        uint256 aggrCurrenteTSTsecondaryUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
        uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
        uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
        uint256 eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
        uint256 eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

        assetTST.mint(address(eTST), eTSTYield);
        assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
        eTST.skim(type(uint256).max, address(eulerAggregationLayer));
        eTSTsecondary.skim(type(uint256).max, address(eulerAggregationLayer));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationLayer.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationLayer.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationLayer)), 0);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerAggregationLayer.convertToAssets(amountToWithdraw)
            );
        }
    }

    function testSingleStrategy_WithYield_WithInterest() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(eulerAggregationLayer.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedStrategyCash);
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(eulerAggregationLayer));

        // harvest
        vm.prank(user1);
        eulerAggregationLayer.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationLayer.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationLayer.redeem(amountToWithdraw, user1, user1);

            // all yield is distributed
            assertApproxEqAbs(eTST.balanceOf(address(eulerAggregationLayer)), 0, 1);
            assertApproxEqAbs(
                eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw, 1
            );
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
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
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory eTSTstrategyBefore = eulerAggregationLayer.getStrategy(address(eTST));
            IEulerAggregationLayer.Strategy memory eTSTsecondarystrategyBefore =
                eulerAggregationLayer.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(
                eulerAggregationLayer.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerAggregationLayer.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerAggregationLayer)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            // mock an increase of aggregator balance due to yield
            uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
            uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
            uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerAggregationLayer));
            uint256 aggrCurrenteTSTsecondaryUnderlyingBalance =
                eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
            uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

            assetTST.mint(address(eTST), eTSTYield);
            assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
            eTST.skim(type(uint256).max, address(eulerAggregationLayer));
            eTSTsecondary.skim(type(uint256).max, address(eulerAggregationLayer));
        }

        // harvest
        vm.prank(user1);
        eulerAggregationLayer.harvest();
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationLayer.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationLayer.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(eTST.balanceOf(address(eulerAggregationLayer)), 0, 0);
            assertApproxEqAbs(
                eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw, 1
            );
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
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
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory eTSTstrategyBefore = eulerAggregationLayer.getStrategy(address(eTST));
            IEulerAggregationLayer.Strategy memory eTSTsecondarystrategyBefore =
                eulerAggregationLayer.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(
                eulerAggregationLayer.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash
            );
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(eulerAggregationLayer))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (eulerAggregationLayer.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(eulerAggregationLayer)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        uint256 eTSTYield;
        uint256 eTSTsecondaryYield;
        {
            // mock an increase of aggregator balance due to yield
            uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
            uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
            uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(eulerAggregationLayer));
            uint256 aggrCurrenteTSTsecondaryUnderlyingBalance =
                eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
            uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
            uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
            eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
            eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

            assetTST.mint(address(eTST), eTSTYield);
            assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
            eTST.skim(type(uint256).max, address(eulerAggregationLayer));
            eTSTsecondary.skim(type(uint256).max, address(eulerAggregationLayer));
        }

        // harvest
        vm.prank(user1);
        eulerAggregationLayer.harvest();
        vm.warp(block.timestamp + 2 weeks);

        vm.prank(manager);
        eulerAggregationLayer.removeStrategy(address(eTSTsecondary));

        {
            uint256 amountToWithdraw = eulerAggregationLayer.balanceOf(user1);

            vm.prank(user1);
            vm.expectRevert(WithdrawalQueue.NotEnoughAssets.selector);
            eulerAggregationLayer.redeem(amountToWithdraw, user1, user1);
        }
    }
}
