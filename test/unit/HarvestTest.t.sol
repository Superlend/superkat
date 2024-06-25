// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    IAggregationLayerVault
} from "../common/AggregationLayerVaultBase.t.sol";

contract HarvestTest is AggregationLayerVaultBase {
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

    function testHarvestWithPositiveYield() public {
        // no yield increase
        IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = aggregationLayerVault.totalAllocated();

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(aggregationLayerVault))) == strategyBefore.allocated);

        vm.prank(user1);
        aggregationLayerVault.harvest();

        assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        assertEq(aggregationLayerVault.totalAllocated(), totalAllocatedBefore);

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(aggregationLayerVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.maxWithdraw(address(aggregationLayerVault));
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        aggregationLayerVault.harvest();

        assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            aggregationLayerVault.totalAllocated(),
            totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );
    }

    function testHarvestNegativeYieldBiggerThanInterestLeft() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(aggregationLayerVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalance * 9e17 / 1e18)
        );

        IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

        uint256 expectedAllocated = eTST.maxWithdraw(address(aggregationLayerVault));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 expectedLoss = strategyBefore.allocated - expectedAllocated;
        uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();

        vm.prank(user1);
        aggregationLayerVault.harvest();

        // check that loss socialized from the deposits
        assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedLoss);
    }

    function testHarvestNegativeYieldSingleUser() public {
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
        vm.stopPrank();

        uint256 user1SharesAfter = aggregationLayerVault.balanceOf(user1);
        uint256 user1AssetsAfter = aggregationLayerVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
    }

    function testHarvestNegativeYieldMultipleUser() public {
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

        vm.prank(user1);
        aggregationLayerVault.harvest();

        uint256 user1SharesAfter = aggregationLayerVault.balanceOf(user1);
        uint256 user1AssetsAfter = aggregationLayerVault.convertToAssets(user1SharesAfter);
        uint256 user2SharesAfter = aggregationLayerVault.balanceOf(user2);
        uint256 user2AssetsAfter = aggregationLayerVault.convertToAssets(user2SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
        assertApproxEqAbs(user2AssetsAfter, expectedUser2Assets, 1);
    }

    function testHarvestWhenInteresetLeftGreaterThanLoss() public {
        IAggregationLayerVault.Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = aggregationLayerVault.totalAllocated();

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(aggregationLayerVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.maxWithdraw(address(aggregationLayerVault));
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        aggregationLayerVault.harvest();

        assertEq((aggregationLayerVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            aggregationLayerVault.totalAllocated(),
            totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 2%
        uint256 aggrCurrentStrategyBalanceAfterNegYield = expectedAllocated * 98e16 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.maxWithdraw.selector, address(aggregationLayerVault)),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        strategyBefore = aggregationLayerVault.getStrategy(address(eTST));
        expectedAllocated = eTST.maxWithdraw(address(aggregationLayerVault));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 user1SharesBefore = aggregationLayerVault.balanceOf(user1);
        uint256 expectedUser1Assets = user1SharesBefore * amountToDeposit / aggregationLayerVault.totalSupply();
        uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
        uint256 interestToBeAccrued = aggregationLayerVault.interestAccrued();

        vm.startPrank(user1);
        aggregationLayerVault.harvest();
        vm.stopPrank();

        uint256 user1SharesAfter = aggregationLayerVault.balanceOf(user1);
        uint256 user1AssetsAfter = aggregationLayerVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets + interestToBeAccrued, 1);
        assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore + interestToBeAccrued);
    }
}
