// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    YieldAggregatorBase,
    YieldAggregator,
    console2,
    EVault,
    IYieldAggregator,
    ErrorsLib
} from "../common/YieldAggregatorBase.t.sol";

contract HarvestTest is YieldAggregatorBase {
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
    }

    function testHarvestWithPositiveYield() public {
        // no yield increase
        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerYieldAggregatorVault.totalAllocated();

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(eulerYieldAggregatorVault))) == strategyBefore.allocated);

        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        assertEq(eulerYieldAggregatorVault.totalAllocated(), totalAllocatedBefore);

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            eulerYieldAggregatorVault.totalAllocated(),
            totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );
    }

    function testHarvestNegativeYieldBiggerThanInterestLeft() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 9e17 / 1e18)
        );

        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 expectedLoss = strategyBefore.allocated - expectedAllocated;
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();

        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        // check that loss socialized from the deposits
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedLoss);
    }

    function testHarvestNegativeYieldSingleUser() public {
        vm.warp(block.timestamp + 86400);

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

        vm.startPrank(user1);
        eulerYieldAggregatorVault.harvest();
        vm.stopPrank();

        uint256 user1SharesAfter = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerYieldAggregatorVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
    }

    function testHarvestNegativeYieldMultipleUser() public {
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

        uint256 negativeYield = strategyBefore.allocated - expectedAllocated;
        uint256 user1SharesBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerYieldAggregatorVault.totalSupply();
        uint256 user2SharesBefore = eulerYieldAggregatorVault.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / eulerYieldAggregatorVault.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerYieldAggregatorVault.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerYieldAggregatorVault.totalSupply() - user2SocializedLoss;

        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        uint256 user1SharesAfter = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerYieldAggregatorVault.convertToAssets(user1SharesAfter);
        uint256 user2SharesAfter = eulerYieldAggregatorVault.balanceOf(user2);
        uint256 user2AssetsAfter = eulerYieldAggregatorVault.convertToAssets(user2SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
        assertApproxEqAbs(user2AssetsAfter, expectedUser2Assets, 1);
    }

    function testHarvestWhenInteresetLeftGreaterThanLoss() public {
        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerYieldAggregatorVault.totalAllocated();

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        assertEq((eulerYieldAggregatorVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            eulerYieldAggregatorVault.totalAllocated(),
            totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 2%
        uint256 aggrCurrentStrategyBalanceAfterNegYield = expectedAllocated * 98e16 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, eTST.balanceOf(address(eulerYieldAggregatorVault))),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        strategyBefore = eulerYieldAggregatorVault.getStrategy(address(eTST));
        expectedAllocated = eTST.previewRedeem(eTST.balanceOf(address(eulerYieldAggregatorVault)));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 user1SharesBefore = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 expectedUser1Assets = user1SharesBefore * amountToDeposit / eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 interestToBeAccrued = eulerYieldAggregatorVault.interestAccrued();

        vm.startPrank(user1);
        eulerYieldAggregatorVault.harvest();
        vm.stopPrank();

        uint256 user1SharesAfter = eulerYieldAggregatorVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerYieldAggregatorVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets + interestToBeAccrued, 1);
        assertEq(eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore + interestToBeAccrued);
    }
}
