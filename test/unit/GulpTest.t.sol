// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    console2,
    EVault,
    IEulerAggregationLayer
} from "../common/EulerAggregationLayerBase.t.sol";

contract GulpTest is EulerAggregationLayerBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

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
    }

    function testGulpAfterNegativeYieldEqualToInterestLeft() public {
        eulerAggregationLayer.gulp();
        EulerAggregationLayer.AggregationVaultSavingRate memory ers =
            eulerAggregationLayer.getAggregationVaultSavingRate();
        assertEq(eulerAggregationLayer.interestAccrued(), 0);
        assertEq(ers.interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerAggregationLayer.gulp();
        assertEq(eulerAggregationLayer.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerAggregationLayer.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerAggregationLayer));
        }
        vm.prank(user1);
        eulerAggregationLayer.harvest();

        assertEq(eulerAggregationLayer.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerAggregationLayer.interestAccrued(), 23809523809523809523);
        eulerAggregationLayer.gulp();
        ers = eulerAggregationLayer.getAggregationVaultSavingRate();
        assertEq(ers.interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerAggregationLayer.gulp();
        ers = eulerAggregationLayer.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by ers.interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationLayer));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - ers.interestLeft;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerAggregationLayer)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerAggregationLayer.harvest();
    }

    function testGulpAfterNegativeYieldBiggerThanInterestLeft() public {
        eulerAggregationLayer.gulp();
        EulerAggregationLayer.AggregationVaultSavingRate memory ers =
            eulerAggregationLayer.getAggregationVaultSavingRate();
        assertEq(eulerAggregationLayer.interestAccrued(), 0);
        assertEq(ers.interestLeft, 0);

        vm.warp(block.timestamp + 2 days);
        eulerAggregationLayer.gulp();
        assertEq(eulerAggregationLayer.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        assertEq(eulerAggregationLayer.interestAccrued(), 0);
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerAggregationLayer));
        }
        vm.prank(user1);
        eulerAggregationLayer.harvest();

        assertEq(eulerAggregationLayer.interestAccrued(), 0);

        vm.warp(block.timestamp + 1 days);
        // interest per day 23.809523809523
        assertEq(eulerAggregationLayer.interestAccrued(), 23809523809523809523);
        eulerAggregationLayer.gulp();
        ers = eulerAggregationLayer.getAggregationVaultSavingRate();
        assertEq(ers.interestLeft, yield - 23809523809523809523);

        // move close to end of smearing
        vm.warp(block.timestamp + 11 days);
        eulerAggregationLayer.gulp();
        ers = eulerAggregationLayer.getAggregationVaultSavingRate();

        // mock a decrease of strategy balance by ers.interestLeft
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationLayer));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance - (ers.interestLeft * 2);
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(eulerAggregationLayer)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );
        vm.prank(user1);
        eulerAggregationLayer.harvest();
    }
}
