// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {FourSixTwoSixAggBase, FourSixTwoSixAgg, console2, EVault} from "../common/FourSixTwoSixAggBase.t.sol";

contract HarvestTest is FourSixTwoSixAggBase {
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
    }

    function testHarvest() public {
        // no yield increase
        FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = fourSixTwoSixAgg.totalAllocated();

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))) == strategyBefore.allocated);

        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));

        assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        assertEq(fourSixTwoSixAgg.totalAllocated(), totalAllocatedBefore);

        // positive yield
        vm.warp(block.timestamp + 86400);

        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(fourSixTwoSixAgg)),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))) > strategyBefore.allocated);

        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));

        assertEq(
            (fourSixTwoSixAgg.getStrategy(address(eTST))).allocated,
            eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg)))
        );
        assertEq(
            fourSixTwoSixAgg.totalAllocated(),
            totalAllocatedBefore
                + (eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))) - strategyBefore.allocated)
        );
    }

    function testHarvestNegativeYield() public {
        vm.warp(block.timestamp + 86400);

        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(fourSixTwoSixAgg)),
            abi.encode(aggrCurrentStrategyBalance * 9e17 / 1e18)
        );

        FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))) < strategyBefore.allocated);

        vm.startPrank(user1);
        vm.expectRevert(FourSixTwoSixAgg.NegativeYield.selector);
        fourSixTwoSixAgg.harvest(address(eTST));
    }
}
