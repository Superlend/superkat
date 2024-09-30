// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract HarvestTest is EulerEarnBase {
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
    }

    function testHarvestWithPositiveYield() public {
        // no yield increase
        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerEulerEarnVault.totalAllocated();

        assertTrue(eTST.convertToAssets(eTST.balanceOf(address(eulerEulerEarnVault))) == strategyBefore.allocated);

        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, strategyBefore.allocated);
        assertEq(eulerEulerEarnVault.totalAllocated(), totalAllocatedBefore);

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            eulerEulerEarnVault.totalAllocated(), totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );
        assertEq(eulerEulerEarnVault.lastHarvestTimestamp(), block.timestamp);
    }

    function testHarvestNegativeYieldBiggerThanInterestLeft() public {
        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 9e17 / 1e18)
        );

        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 expectedLoss = strategyBefore.allocated - expectedAllocated;
        uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();

        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        // check that loss socialized from the deposits
        assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedLoss);
    }

    function testHarvestNegativeYieldSingleUser() public {
        vm.warp(block.timestamp + 86400);

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

        vm.startPrank(user1);
        eulerEulerEarnVault.harvest();
        vm.stopPrank();

        uint256 user1SharesAfter = eulerEulerEarnVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerEulerEarnVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
    }

    function testHarvestNegativeYieldMultipleUser() public {
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

        uint256 negativeYield = strategyBefore.allocated - expectedAllocated;
        uint256 user1SharesBefore = eulerEulerEarnVault.balanceOf(user1);
        uint256 user1SocializedLoss = user1SharesBefore * negativeYield / eulerEulerEarnVault.totalSupply();
        uint256 user2SharesBefore = eulerEulerEarnVault.balanceOf(user2);
        uint256 user2SocializedLoss = user2SharesBefore * negativeYield / eulerEulerEarnVault.totalSupply();

        uint256 expectedUser1Assets = user1SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerEulerEarnVault.totalSupply() - user1SocializedLoss;
        uint256 expectedUser2Assets = user2SharesBefore * (amountToDeposit + user2InitialBalance)
            / eulerEulerEarnVault.totalSupply() - user2SocializedLoss;

        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        uint256 user1SharesAfter = eulerEulerEarnVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerEulerEarnVault.convertToAssets(user1SharesAfter);
        uint256 user2SharesAfter = eulerEulerEarnVault.balanceOf(user2);
        uint256 user2AssetsAfter = eulerEulerEarnVault.convertToAssets(user2SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets, 1);
        assertApproxEqAbs(user2AssetsAfter, expectedUser2Assets, 1);
    }

    function testHarvestWhenInteresetLeftGreaterThanLoss() public {
        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerEulerEarnVault.totalAllocated();

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 aggrCurrentStrategyBalance = eTST.balanceOf(address(eulerEulerEarnVault));
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, aggrCurrentStrategyBalance),
            abi.encode(aggrCurrentStrategyBalance * 11e17 / 1e18)
        );

        uint256 expectedAllocated = eTST.previewRedeem(aggrCurrentStrategyBalance);
        assertTrue(expectedAllocated > strategyBefore.allocated);

        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        assertEq((eulerEulerEarnVault.getStrategy(address(eTST))).allocated, expectedAllocated);
        assertEq(
            eulerEulerEarnVault.totalAllocated(), totalAllocatedBefore + (expectedAllocated - strategyBefore.allocated)
        );

        vm.warp(block.timestamp + 86400);

        // mock a decrease of strategy balance by 2%
        uint256 aggrCurrentStrategyBalanceAfterNegYield = expectedAllocated * 98e16 / 1e18;
        vm.mockCall(
            address(eTST),
            abi.encodeWithSelector(EVault.previewRedeem.selector, eTST.balanceOf(address(eulerEulerEarnVault))),
            abi.encode(aggrCurrentStrategyBalanceAfterNegYield)
        );

        strategyBefore = eulerEulerEarnVault.getStrategy(address(eTST));
        expectedAllocated = eTST.previewRedeem(eTST.balanceOf(address(eulerEulerEarnVault)));
        assertTrue(expectedAllocated < strategyBefore.allocated);

        uint256 user1SharesBefore = eulerEulerEarnVault.balanceOf(user1);
        uint256 expectedUser1Assets = user1SharesBefore * amountToDeposit / eulerEulerEarnVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
        uint256 interestToBeAccrued = eulerEulerEarnVault.interestAccrued();

        vm.startPrank(user1);
        eulerEulerEarnVault.harvest();
        vm.stopPrank();

        uint256 user1SharesAfter = eulerEulerEarnVault.balanceOf(user1);
        uint256 user1AssetsAfter = eulerEulerEarnVault.convertToAssets(user1SharesAfter);

        assertApproxEqAbs(user1AssetsAfter, expectedUser1Assets + interestToBeAccrued, 1);
        assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore + interestToBeAccrued);
    }
}
