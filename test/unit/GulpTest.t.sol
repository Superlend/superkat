// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    Strategy
} from "../common/AggregationLayerVaultBase.t.sol";

contract GulpTest is AggregationLayerVaultBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

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
    }

    function testGulpAfterNegativeYieldEqualToInterestLeft() public {
        aggregationLayerVault.gulp();
        AggregationLayerVault.AggregationVaultSavingRate memory ers =
            aggregationLayerVault.getAggregationVaultSavingRate();
        assertEq(aggregationLayerVault.interestAccrued(), 0);
        assertEq(ers.interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        aggregationLayerVault.gulp();
        assertEq(aggregationLayerVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(aggregationLayerVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(aggregationLayerVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(aggregationLayerVault));
        }
        vm.prank(user1);
        aggregationLayerVault.harvest();

        assertEq(aggregationLayerVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(aggregationLayerVault.interestAccrued(), 23809523809523809523);
        aggregationLayerVault.gulp();
        ers = aggregationLayerVault.getAggregationVaultSavingRate();
        assertEq(ers.interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        aggregationLayerVault.gulp();
        ers = aggregationLayerVault.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by ers.interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - ers.interestLeft;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        aggregationLayerVault.harvest();
    }

    function testGulpAfterNegativeYieldBiggerThanInterestLeft() public {
        aggregationLayerVault.gulp();
        AggregationLayerVault.AggregationVaultSavingRate memory ers =
            aggregationLayerVault.getAggregationVaultSavingRate();
        assertEq(aggregationLayerVault.interestAccrued(), 0);
        assertEq(ers.interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        aggregationLayerVault.gulp();
        assertEq(aggregationLayerVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(aggregationLayerVault.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(aggregationLayerVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(aggregationLayerVault));
        }
        vm.prank(user1);
        aggregationLayerVault.harvest();

        assertEq(aggregationLayerVault.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(aggregationLayerVault.interestAccrued(), 23809523809523809523);
        aggregationLayerVault.gulp();
        ers = aggregationLayerVault.getAggregationVaultSavingRate();
        assertEq(ers.interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        aggregationLayerVault.gulp();
        ers = aggregationLayerVault.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by ers.interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - (ers.interestLeft * 2);
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        aggregationLayerVault.harvest();
    }
}
