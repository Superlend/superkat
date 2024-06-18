// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    FourSixTwoSixAggBase, FourSixTwoSixAgg, console2, EVault, Strategy
} from "../common/FourSixTwoSixAggBase.t.sol";

contract GulpTest is FourSixTwoSixAggBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

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
            Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), strategyBefore.allocated);

            uint256 expectedStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable() * strategyBefore.allocationPoints
                / fourSixTwoSixAgg.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(fourSixTwoSixAgg), strategiesToRebalance);

            assertEq(fourSixTwoSixAgg.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), expectedStrategyCash);
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }
    }

    function testGulpAfterNegativeYieldEqualToInterestLeft() public {
        fourSixTwoSixAgg.gulp();
        FourSixTwoSixAgg.AggregationVaultSavingRate memory ers = fourSixTwoSixAgg.getAggregationVaultSavingRate();
        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);
        assertEq(ers.interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        fourSixTwoSixAgg.gulp();
        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(fourSixTwoSixAgg));
        }
        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));

        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(fourSixTwoSixAgg.interestAccrued(), 23809523809523809523);
        fourSixTwoSixAgg.gulp();
        ers = fourSixTwoSixAgg.getAggregationVaultSavingRate();
        assertEq(ers.interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        fourSixTwoSixAgg.gulp();
        ers = fourSixTwoSixAgg.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by ers.interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - ers.interestLeft;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(fourSixTwoSixAgg)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));
    }

    function testGulpAfterNegativeYieldBiggerThanInterestLeft() public {
        fourSixTwoSixAgg.gulp();
        FourSixTwoSixAgg.AggregationVaultSavingRate memory ers = fourSixTwoSixAgg.getAggregationVaultSavingRate();
        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);
        assertEq(ers.interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        fourSixTwoSixAgg.gulp();
        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(fourSixTwoSixAgg));
        }
        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));

        assertEq(fourSixTwoSixAgg.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(fourSixTwoSixAgg.interestAccrued(), 23809523809523809523);
        fourSixTwoSixAgg.gulp();
        ers = fourSixTwoSixAgg.getAggregationVaultSavingRate();
        assertEq(ers.interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        fourSixTwoSixAgg.gulp();
        ers = fourSixTwoSixAgg.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by ers.interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - (ers.interestLeft * 2);
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(fourSixTwoSixAgg)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));
    }
}
