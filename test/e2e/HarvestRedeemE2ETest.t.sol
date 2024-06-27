// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    IAggregationLayerVault
} from "../common/AggregationLayerVaultBase.t.sol";

contract HarvestRedeemE2ETest is AggregationLayerVaultBase {
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
            IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

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

    function testHarvestNegativeYieldAndRedeemSingleUser() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        uint256 expectedAllocated = eTST.maxWithdraw(address(aggregationLayerVault));
        IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - eTST.maxWithdraw(address(aggregationLayerVault));

        uint256 user1SharesBefore = aggregationLayerVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / aggregationLayerVault.totalSupply();
        uint256 expectedUser1Assets =
            user1SharesBefore * amountToDeposit / aggregationLayerVault.totalSupply() - user1SocializedLoss;
        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

        vm.startPrank(user1);
        aggregationLayerVault.harvest();
        aggregationLayerVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        uint256 user1SharesAfter = aggregationLayerVault.balanceOf(user1);

        assertEq(user1SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertEq(aggregationLayerVault.totalAssetsDeposited(), 0);
    }

    function testHarvestNegativeYieldAndRedeemMultipleUser() public {
        uint256 user2InitialBalance = 5000e18;
        assetTST.mint(user2, user2InitialBalance);
        // deposit into aggregator
        {
            vm.startPrank(user2);
            assetTST.approve(address(aggregationLayerVault), user2InitialBalance);
            aggregationLayerVault.deposit(user2InitialBalance, user2);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(aggregationLayerVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));
        uint256 expectedAllocated = eTST.maxWithdraw(address(aggregationLayerVault));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - eTST.maxWithdraw(address(aggregationLayerVault));
        uint256 user1SharesBefore = aggregationLayerVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / aggregationLayerVault.totalSupply();
        uint256 user2SharesBefore = aggregationLayerVault.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / aggregationLayerVault.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / aggregationLayerVault.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / aggregationLayerVault.totalSupply() - user2SocializedLoss;

        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
        uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);

        vm.startPrank(user1);
        aggregationLayerVault.harvest();
        aggregationLayerVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        vm.prank(user2);
        aggregationLayerVault.redeem(user2SharesBefore, user2, user2);

        uint256 user1SharesAfter = aggregationLayerVault.balanceOf(user1);
        uint256 user2SharesAfter = aggregationLayerVault.balanceOf(user2);

        assertEq(user1SharesAfter, 0);
        assertEq(user2SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertApproxEqAbs(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore + expectedUser2Assets, 1);
        assertEq(aggregationLayerVault.totalAssetsDeposited(), 0);
    }
}
