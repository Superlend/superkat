// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEulerAggregationVault,
    ErrorsLib
} from "../common/EulerAggregationVaultBase.t.sol";

contract HarvestTest is EulerAggregationVaultBase {
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
            eulerAggregationVault.rebalance(strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }
    }

    function testHarvestWithPositiveYield() public {
        // no yield increase
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerAggregationVault.totalAllocated();

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))) == strategyBefore.allocated);

        vm.prank(user1);
        eulerAggregationVault.harvest();

        assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        assertEq(eulerAggregationVault.totalAllocated(), totalAllocatedBefore);

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        eulerAggregationVault.harvest();

        assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            eulerAggregationVault.totalAllocated(),
            totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );
    }

    function testHarvestNegativeYieldBiggerThanInterestLeft() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 9e17 / 1e18)
        );

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 expectedLoss = strategyBefore.allocated - expectedAllocated;
        uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();

        vm.prank(user1);
        eulerAggregationVault.harvest();

        // check that loss socialized from the deposits
        assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedLoss);
    }

    function testHarvestNegativeYieldSingleUser() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        uint256 aggrCurrentStrategyBalanceAfterNegYield = aggrCurrentStrategyBalance * 9e17 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - expectedAllocated;

        uint256 user1SharesBefore = eulerAggregationVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerAggregationVault.totalSupply();
        uint256 expectedUser1Assets =
            user1SharesBefore * amountToDeposit / eulerAggregationVault.totalSupply() - user1SocializedLoss;

        vm.startPrank(user1);
        eulerAggregationVault.harvest();
        vm.stopPrank();

        uint256 user1SharesAfter = eulerAggregationVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerAggregationVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
    }

    function testHarvestNegativeYieldMultipleUser() public {
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
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 negativeYield = strategyBefore.allocated - expectedAllocated;
        uint256 user1SharesBefore = eulerAggregationVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerAggregationVault.totalSupply();
        uint256 user2SharesBefore = eulerAggregationVault.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / eulerAggregationVault.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerAggregationVault.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerAggregationVault.totalSupply() - user2SocializedLoss;

        vm.prank(user1);
        eulerAggregationVault.harvest();

        uint256 user1SharesAfter = eulerAggregationVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerAggregationVault.convertToAssets(user1SharesAfter);
        uint256 user2SharesAfter = eulerAggregationVault.balanceOf(user2);
        uint256 user2AssetsAfter = eulerAggregationVault.convertToAssets(user2SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
        assertApproxEqAbs(user2AssetsAfter, expectedUser2Assets, 1);
    }

    function testHarvestWhenInteresetLeftGreaterThanLoss() public {
        IEulerAggregationVault.Strategy memory strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerAggregationVault.totalAllocated();

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerAggregationVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        eulerAggregationVault.harvest();

        assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            eulerAggregationVault.totalAllocated(),
            totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 2%
        uint256 aggrCurrentStrategyBalanceAfterNegYield = expectedAllocated * 98e16 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, eTST.balanceOf(address(eulerAggregationVault))),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        strategyBefore = eulerAggregationVault.getStrategy(address(eTST));
        expectedAllocated = eTST.previewRedeem(eTST.balanceOf(address(eulerAggregationVault)));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 user1SharesBefore = eulerAggregationVault.balanceOf(user1);
        uint256 expectedUser1Assets = user1SharesBefore * amountToDeposit / eulerAggregationVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
        uint256 interestToBeAccrued = eulerAggregationVault.interestAccrued();

        vm.startPrank(user1);
        eulerAggregationVault.harvest();
        vm.stopPrank();

        uint256 user1SharesAfter = eulerAggregationVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerAggregationVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets + interestToBeAccrued, 1);
        assertEq(eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore + interestToBeAccrued);
    }
}
