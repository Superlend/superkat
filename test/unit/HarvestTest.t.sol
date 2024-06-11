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
            rebalancer.rebalance(address(fourSixTwoSixAgg), address(eTST));

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
        uint256 expectedAllocated = eTST.maxWithdraw(address(fourSixTwoSixAgg));

        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));

        assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            fourSixTwoSixAgg.totalAllocated(), totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );
    }

    function testHarvestNegativeYield() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(fourSixTwoSixAgg)),
            abi.encode(aggrCurrentStrategyBalance * 9e17 / 1e18)
        );

        FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))) < strategyBefore.allocated);

        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));
    }

    function testHarvestNegativeYieldAndWithdrawSingleUser() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(fourSixTwoSixAgg)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));
        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))) < strategyBefore.allocated);
        uint256 negativeYield = strategyBefore.allocated - eTST.maxWithdraw(address(fourSixTwoSixAgg));

        uint256 user1SharesBefore = fourSixTwoSixAgg.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / fourSixTwoSixAgg.totalSupply();
        uint256 expectedUser1Assets =
            user1SharesBefore * amountToDeposit / fourSixTwoSixAgg.totalSupply() - user1SocializedLoss;
        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

        vm.startPrank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));
        fourSixTwoSixAgg.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        uint256 user1SharesAfter = fourSixTwoSixAgg.balanceOf(user1);

        assertEq(user1SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
    }

    function testHarvestNegativeYieldwMultipleUser() public {
        uint256 user2InitialBalance = 5000e18;
        assetTST.mint(user2, user2InitialBalance);
        // deposit into aggregator
        {
            vm.startPrank(user2);
            assetTST.approve(address(fourSixTwoSixAgg), user2InitialBalance);
            fourSixTwoSixAgg.deposit(user2InitialBalance, user2);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.balanceOf.selector, address(fourSixTwoSixAgg)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));
        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))) < strategyBefore.allocated);
        uint256 negativeYield = strategyBefore.allocated - eTST.maxWithdraw(address(fourSixTwoSixAgg));
        uint256 user1SharesBefore = fourSixTwoSixAgg.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / fourSixTwoSixAgg.totalSupply();
        uint256 user2SharesBefore = fourSixTwoSixAgg.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / fourSixTwoSixAgg.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / fourSixTwoSixAgg.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / fourSixTwoSixAgg.totalSupply() - user2SocializedLoss;

        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));

        uint256 user1SharesAfter = fourSixTwoSixAgg.balanceOf(user1);
        uint256 user1AssetsAfter = fourSixTwoSixAgg.convertToAssets(user1SharesAfter);
        uint256 user2SharesAfter = fourSixTwoSixAgg.balanceOf(user2);
        uint256 user2AssetsAfter = fourSixTwoSixAgg.convertToAssets(user2SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
        assertApproxEqAbs(user2AssetsAfter, expectedUser2Assets, 1);
    }
}
