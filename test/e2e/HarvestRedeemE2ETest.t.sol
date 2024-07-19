// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEulerAggregationVault
} from "../common/EulerAggregationVaultBase.t.sol";

contract HarvestRedeemE2ETest is EulerAggregationVaultBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

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
            eulerAggregationVault.executeRebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }
    }

    function testHarvestNegativeYieldAndRedeemSingleUser() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(eulerAggregationVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        uint256 expectedAllocated = eTST.maxWithdraw(address(eulerAggregationVault));
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - eTST.maxWithdraw(address(eulerAggregationVault));

        uint256 user1SharesBefore = eulerAggregationVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerAggregationVault.totalSupply();
        uint256 expectedUser1Assets =
            user1SharesBefore * amountToDeposit / eulerAggregationVault.totalSupply() - user1SocializedLoss;
        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

        vm.startPrank(user1);
        eulerAggregationVault.harvest();
        eulerAggregationVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        uint256 user1SharesAfter = eulerAggregationVault.balanceOf(user1);

        assertEq(user1SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertEq(eulerAggregationVault.totalAssetsDeposited(), 0);
    }

    function testHarvestNegativeYieldAndRedeemMultipleUser() public {
        uint256 user2InitialBalance = 5000e18;
        assetTST.mint(user2, user2InitialBalance);
        // deposit into aggregator
        {
            vm.startPrank(user2);
            assetTST.approve(address(eulerAggregationVault), user2InitialBalance);
            eulerAggregationVault.deposit(user2InitialBalance, user2);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(eulerAggregationVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
        uint256 expectedAllocated = eTST.maxWithdraw(address(eulerAggregationVault));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - eTST.maxWithdraw(address(eulerAggregationVault));
        uint256 user1SharesBefore = eulerAggregationVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerAggregationVault.totalSupply();
        uint256 user2SharesBefore = eulerAggregationVault.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / eulerAggregationVault.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerAggregationVault.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerAggregationVault.totalSupply() - user2SocializedLoss;

        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
        uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);

        vm.startPrank(user1);
        eulerAggregationVault.harvest();
        eulerAggregationVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        vm.prank(user2);
        eulerAggregationVault.redeem(user2SharesBefore, user2, user2);

        uint256 user1SharesAfter = eulerAggregationVault.balanceOf(user1);
        uint256 user2SharesAfter = eulerAggregationVault.balanceOf(user2);

        assertEq(user1SharesAfter, 0);
        assertEq(user2SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertApproxEqAbs(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore + expectedUser2Assets, 1);
        assertEq(eulerAggregationVault.totalAssetsDeposited(), 0);
    }
}
