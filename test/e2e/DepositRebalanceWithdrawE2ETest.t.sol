// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    FourSixTwoSixAggBase,
    FourSixTwoSixAgg,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20
} from "../common/FourSixTwoSixAggBase.t.sol";

contract DepositRebalanceWithdrawE2ETest is FourSixTwoSixAggBase {
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
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), strategyBefore.allocated);

            uint256 expectedStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable() * strategyBefore.allocationPoints
                / fourSixTwoSixAgg.totalAllocationPoints();

            vm.prank(user1);
            fourSixTwoSixAgg.rebalance(address(eTST));

            assertEq(fourSixTwoSixAgg.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), expectedStrategyCash);
            assertEq(
                (fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, strategyBefore.allocated + expectedStrategyCash
            );
        }

        vm.warp(block.timestamp + 86400);
        // partial withdraw, no need to withdraw from strategy as cash reserve is enough
        uint256 amountToWithdraw = 6000e18;
        {
            FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));
            uint256 strategyShareBalanceBefore = eTST.balanceOf(address(fourSixTwoSixAgg));
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            fourSixTwoSixAgg.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(fourSixTwoSixAgg)), strategyShareBalanceBefore);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(fourSixTwoSixAgg.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        }

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            amountToWithdraw = amountToDeposit - amountToWithdraw;
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            fourSixTwoSixAgg.withdraw(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(fourSixTwoSixAgg)), 0);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(fourSixTwoSixAgg.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToWithdraw);
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, 0);
        }
    }

    function testSingleStrategy_WithYield() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), strategyBefore.allocated);

            uint256 expectedStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable() * strategyBefore.allocationPoints
                / fourSixTwoSixAgg.totalAllocationPoints();

            vm.prank(user1);
            fourSixTwoSixAgg.rebalance(address(eTST));

            assertEq(fourSixTwoSixAgg.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), expectedStrategyCash);
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(fourSixTwoSixAgg));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            fourSixTwoSixAgg.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(fourSixTwoSixAgg)), yield);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(fourSixTwoSixAgg.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + fourSixTwoSixAgg.convertToAssets(amountToWithdraw)
            );
        }
    }

    function testMultipleStrategy_WithYield() public {
        IEVault eTSTsecondary;
        {
            eTSTsecondary = IEVault(coreProductLine.createVault(address(assetTST), address(oracle), unitOfAccount));
            eTSTsecondary.setInterestRateModel(address(new IRMTestDefault()));

            uint256 initialStrategyAllocationPoints = 1000e18;
            _addStrategy(manager, address(eTSTsecondary), initialStrategyAllocationPoints);
        }

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        // 2500 total points; 1000 for reserve(40%), 500(20%) for eTST, 1000(40%) for eTSTsecondary
        // 10k deposited; 4000 for reserve, 2000 for eTST, 4000 for eTSTsecondary
        vm.warp(block.timestamp + 86400);
        {
            FourSixTwoSixAgg.Strategy memory eTSTstrategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));
            FourSixTwoSixAgg.Strategy memory eTSTsecondarystrategyBefore =
                fourSixTwoSixAgg.getStrategy(address(eTSTsecondary));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), eTSTstrategyBefore.allocated);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(fourSixTwoSixAgg))),
                eTSTsecondarystrategyBefore.allocated
            );

            uint256 expectedeTSTStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable()
                * eTSTstrategyBefore.allocationPoints / fourSixTwoSixAgg.totalAllocationPoints();
            uint256 expectedeTSTsecondaryStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable()
                * eTSTsecondarystrategyBefore.allocationPoints / fourSixTwoSixAgg.totalAllocationPoints();

            assertTrue(expectedeTSTStrategyCash != 0);
            assertTrue(expectedeTSTsecondaryStrategyCash != 0);

            address[] memory strategiesToRebalance = new address[](2);
            strategiesToRebalance[0] = address(eTST);
            strategiesToRebalance[1] = address(eTSTsecondary);
            vm.prank(user1);
            fourSixTwoSixAgg.rebalanceMultipleStrategies(strategiesToRebalance);

            assertEq(fourSixTwoSixAgg.totalAllocated(), expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), expectedeTSTStrategyCash);
            assertEq(
                eTSTsecondary.convertToAssets(eTSTsecondary.balanceOf(address(fourSixTwoSixAgg))),
                expectedeTSTsecondaryStrategyCash
            );
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, expectedeTSTStrategyCash);
            assertEq(
                (fourSixTwoSixAgg.getStrategy(address(eTSTsecondary))).allocated, expectedeTSTsecondaryStrategyCash
            );
            assertEq(
                assetTST.balanceOf(address(fourSixTwoSixAgg)),
                amountToDeposit - (expectedeTSTStrategyCash + expectedeTSTsecondaryStrategyCash)
            );
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of aggregator balance due to yield
        uint256 aggrCurrenteTSTShareBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrenteTSTUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTShareBalance);
        uint256 aggrCurrenteTSTsecondaryShareBalance = eTSTsecondary.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrenteTSTsecondaryUnderlyingBalance = eTST.convertToAssets(aggrCurrenteTSTsecondaryShareBalance);
        uint256 aggrNeweTSTUnderlyingBalance = aggrCurrenteTSTUnderlyingBalance * 11e17 / 1e18;
        uint256 aggrNeweTSTsecondaryUnderlyingBalance = aggrCurrenteTSTsecondaryUnderlyingBalance * 11e17 / 1e18;
        uint256 eTSTYield = aggrNeweTSTUnderlyingBalance - aggrCurrenteTSTUnderlyingBalance;
        uint256 eTSTsecondaryYield = aggrNeweTSTsecondaryUnderlyingBalance - aggrCurrenteTSTsecondaryUnderlyingBalance;

        assetTST.mint(address(eTST), eTSTYield);
        assetTST.mint(address(eTSTsecondary), eTSTsecondaryYield);
        eTST.skim(type(uint256).max, address(fourSixTwoSixAgg));
        eTSTsecondary.skim(type(uint256).max, address(fourSixTwoSixAgg));

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            fourSixTwoSixAgg.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(fourSixTwoSixAgg)), 0);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(fourSixTwoSixAgg.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + fourSixTwoSixAgg.convertToAssets(amountToWithdraw)
            );
        }
    }

    function testSingleStrategy_WithYield_WithInterest() public {
        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), strategyBefore.allocated);

            uint256 expectedStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable() * strategyBefore.allocationPoints
                / fourSixTwoSixAgg.totalAllocationPoints();

            vm.prank(user1);
            fourSixTwoSixAgg.rebalance(address(eTST));

            assertEq(fourSixTwoSixAgg.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), expectedStrategyCash);
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
        uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
        uint256 yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
        assetTST.mint(address(eTST), yield);
        eTST.skim(type(uint256).max, address(fourSixTwoSixAgg));

        // harvest
        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));
        vm.warp(block.timestamp + 2 weeks);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            fourSixTwoSixAgg.redeem(amountToWithdraw, user1, user1);

            // all yield is distributed
            assertApproxEqAbs(eTST.balanceOf(address(fourSixTwoSixAgg)), 0, 1);
            assertApproxEqAbs(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw, 1);
            assertEq(fourSixTwoSixAgg.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + amountToDeposit + yield, 1);
        }
    }
}
