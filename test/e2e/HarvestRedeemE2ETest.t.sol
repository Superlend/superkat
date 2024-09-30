// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract HarvestRedeemE2ETest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;
    uint256 amountToDeposit = 10000e18;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

        // deposit into EulerEarn
        {
            uint256 balanceBefore = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
            eulerEulerEarnVault.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerEulerEarnVault.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerEulerEarnVault.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerEulerEarnVault.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            eulerEulerEarnVault.rebalance(strategiesToRebalance);

            assertEq(eulerEulerEarnVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))), expectedStrategyCash);
            assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 1.5 days);
    }

    function testHarvestNegativeYieldAndRedeemSingleUser() public {
        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - expectedAllocated;

        uint256 user1SharesBefore = eulerEulerEarnVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerEulerEarnVault.totalSupply();
        uint256 expectedUser1Assets =
            user1SharesBefore * amountToDeposit / eulerEulerEarnVault.totalSupply() - user1SocializedLoss;
        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

        uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(user1SharesBefore);
        vm.startPrank(user1);
        uint256 withdrawnAssets = eulerEulerEarnVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        uint256 user1SharesAfter = eulerEulerEarnVault.balanceOf(user1);

        assertEq(user1SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertEq(eulerEulerEarnVault.totalAssetsDeposited(), 0);
        assertEq(previewedAssets, withdrawnAssets);
    }

    function testHarvestNegativeYieldAndRedeemMultipleUser() public {
        uint256 user2InitialBalance = 5000e18;
        assetTST.mint(user2, user2InitialBalance);
        // deposit into EulerEarn
        {
            vm.startPrank(user2);
            assetTST.approve(address(eulerEulerEarnVault), user2InitialBalance);
            eulerEulerEarnVault.deposit(user2InitialBalance, user2);
            vm.stopPrank();
        }

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - eTST.previewRedeem(aggrCurrentStrategyBalance);
        uint256 user1SharesBefore = eulerEulerEarnVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerEulerEarnVault.totalSupply();
        uint256 user2SharesBefore = eulerEulerEarnVault.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / eulerEulerEarnVault.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerEulerEarnVault.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerEulerEarnVault.totalSupply() - user2SocializedLoss;

        uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
        uint256 user2AssetTSTBalanceBefore = assetTST.balanceOf(user2);

        uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(user1SharesBefore);
        vm.startPrank(user1);
        uint256 withdrawnAssets = eulerEulerEarnVault.redeem(user1SharesBefore, user1, user1);
        vm.stopPrank();

        assertEq(previewedAssets, withdrawnAssets);

        previewedAssets = eulerEulerEarnVault.previewRedeem(user2SharesBefore);
        vm.prank(user2);
        withdrawnAssets = eulerEulerEarnVault.redeem(user2SharesBefore, user2, user2);

        assertEq(previewedAssets, withdrawnAssets);

        uint256 user1SharesAfter = eulerEulerEarnVault.balanceOf(user1);
        uint256 user2SharesAfter = eulerEulerEarnVault.balanceOf(user2);

        assertEq(user1SharesAfter, 0);
        assertEq(user2SharesAfter, 0);
        assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedUser1Assets, 1);
        assertApproxEqAbs(assetTST.balanceOf(user2), user2AssetTSTBalanceBefore + expectedUser2Assets, 1);
        assertEq(eulerEulerEarnVault.totalAssetsDeposited(), 0);
    }
}
