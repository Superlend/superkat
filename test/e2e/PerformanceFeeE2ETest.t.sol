// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";

contract PerformanceFeeE2ETest is YieldAggregatorBase {
    uint256 user1InitialBalance = 100000e18;

    address feeRecipient;

    function setUp() public virtual override {
        super.setUp();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

        feeRecipient = makeAddr("FEE_RECIPIENT");
    }

    function testSetPerformanceFee() public {
        (address feeRecipientAddr, uint256 fee) = eulerYieldAggregatorVault.performanceFeeConfig();
        assertEq(fee, 0);
        assertEq(feeRecipientAddr, address(0));

        uint96 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerYieldAggregatorVault.setFeeRecipient(feeRecipient);
        eulerYieldAggregatorVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        (feeRecipientAddr, fee) = eulerYieldAggregatorVault.performanceFeeConfig();
        assertEq(fee, newPerformanceFee);
        assertEq(feeRecipientAddr, feeRecipient);
    }

    function testHarvestWithFeeEnabled() public {
        uint96 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerYieldAggregatorVault.setFeeRecipient(feeRecipient);
        eulerYieldAggregatorVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;

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

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerYieldAggregatorVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerYieldAggregatorVault));
        }

        (, uint256 performanceFee) = eulerYieldAggregatorVault.performanceFeeConfig();
        uint256 expectedPerformanceFeeAssets = yield * performanceFee / 1e18;
        uint256 expectedPerformanceFeeShares = eulerYieldAggregatorVault.previewDeposit(expectedPerformanceFeeAssets);

        IYieldAggregator.Strategy memory strategyBeforeHarvest = eulerYieldAggregatorVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerYieldAggregatorVault.totalAllocated();

        uint256 previewedAssets = eulerYieldAggregatorVault.previewRedeem(eulerYieldAggregatorVault.balanceOf(user1));

        // harvest
        vm.prank(user1);
        eulerYieldAggregatorVault.harvest();

        assertGt(expectedPerformanceFeeShares, 0);
        assertEq(assetTST.balanceOf(feeRecipient), 0);
        assertEq(eulerYieldAggregatorVault.balanceOf(feeRecipient), expectedPerformanceFeeShares);
        assertEq(
            eulerYieldAggregatorVault.getStrategy(address(eTST)).allocated, strategyBeforeHarvest.allocated + yield
        );
        assertEq(eulerYieldAggregatorVault.totalAllocated(), totalAllocatedBefore + yield);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerYieldAggregatorVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssetTST =
                eulerYieldAggregatorVault.convertToAssets(eulerYieldAggregatorVault.balanceOf(user1));

            vm.prank(user1);
            uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(
                eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssetTST, 1
            );
            assertEq(eulerYieldAggregatorVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssetTST, 1);
            assertEq(withdrawnAssets, previewedAssets);
        }

        // full redemption of recipient fees
        {
            uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
            uint256 assetTSTBalanceBefore = assetTST.balanceOf(feeRecipient);

            uint256 feeShares = eulerYieldAggregatorVault.balanceOf(feeRecipient);
            uint256 expectedAssets = eulerYieldAggregatorVault.convertToAssets(feeShares);
            assertGt(expectedAssets, 0);

            vm.prank(feeRecipient);
            eulerYieldAggregatorVault.redeem(feeShares, feeRecipient, feeRecipient);

            assertApproxEqAbs(
                eulerYieldAggregatorVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets, 1
            );
            assertEq(eulerYieldAggregatorVault.totalSupply(), 0);
            assertApproxEqAbs(assetTST.balanceOf(feeRecipient), assetTSTBalanceBefore + expectedAssets, 1);
        }
    }
}
