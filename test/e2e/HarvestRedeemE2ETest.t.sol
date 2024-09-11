// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract HarvestRedeemE2ETest is YieldAggregatorBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
            eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerYieldAggregatorVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerYieldAggregatorVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerYieldAggregatorVault.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerYieldAggregatorVault.rebalance(strategiesToRebalance);

            assertEq(eulerYieldAggregatorVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))), expectedStrategyCash);
            assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 1.5 days);
    }

    function testHarvestNegativeYieldAndRedeemSingleUser() public {
        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - expectedAllocated;

        uint256 user1SharesBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerYieldAggregatorVault.totalSupply();
        uint256 expectedUser1Assets =
            user1SharesBefore * amountToDeposit / eulerYieldAggregatorVault.totalSupply() - user1SocializedLoss;
        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

        uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(user1SharesBefore);
        vm.startPrank(user1);
        uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        uint256 user1SharesAfter = eulerYieldAggregatorVault.balanceOf(user1);

        assertEq(user1SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), 0);
        assertEq(previewedAssets, withdrawnAssets);
    }

    function testHarvestNegativeYieldAndRedeemMultipleUser() public {
        uint256 user2InitialBalance = 5000e18;
        assetTST.mint(user2, user2InitialBalance);
        // deposit into aggregator
        {
            vm.startPrank(user2);
            assetTST.approve(address(eulerYieldAggregatorVault), user2InitialBalance);
            eulerYieldAggregatorVault.deposit(user2InitialBalance, user2);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - eTST.previewRedeem(aggrCurrentStrategyBalance);
        uint256 user1SharesBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerYieldAggregatorVault.totalSupply();
        uint256 user2SharesBefore = eulerYieldAggregatorVault.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / eulerYieldAggregatorVault.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerYieldAggregatorVault.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerYieldAggregatorVault.totalSupply() - user2SocializedLoss;

        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
        uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);

        uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(user1SharesBefore);
        vm.startPrank(user1);
        uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        assertEq(previewedAssets, withdrawnAssets);

        previewedAssets = eulerYieldAggregatorVault.previewRedeem(user2SharesBefore);
        vm.prank(user2);
        withdrawnAssets = eulerYieldAggregatorVault.redeem(user2SharesBefore, user2, user2);

        assertEq(previewedAssets, withdrawnAssets);

        uint256 user1SharesAfter = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 user2SharesAfter = eulerYieldAggregatorVault.balanceOf(user2);

        assertEq(user1SharesAfter, 0);
        assertEq(user2SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertApproxEqAbs(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore + expectedUser2Assets, 1);
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), 0);
    }
}
