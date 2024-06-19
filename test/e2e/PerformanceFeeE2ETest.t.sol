// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    Strategy
} from "../common/AggregationLayerVaultBase.t.sol";

contract PerformanceFeeE2ETest is AggregationLayerVaultBase {
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
        {
            (, uint256 fee) = aggregationLayerVault.performanceFeeConfig();
            assertEq(fee, 0);
        }

        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        aggregationLayerVault.setFeeRecipient(feeRecipient);
        aggregationLayerVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        (address feeRecipientAddr, uint256 fee) = aggregationLayerVault.performanceFeeConfig();
        assertEq(fee, newPerformanceFee);
        assertEq(feeRecipientAddr, feeRecipient);
    }

    function testHarvestWithFeeEnabled() public {
        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        aggregationLayerVault.setFeeRecipient(feeRecipient);
        aggregationLayerVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;

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
            Strategy memory strategyBefore = aggregationLayerVault.getStrategy(address(eTST));

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

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(aggregationLayerVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(aggregationLayerVault));
        }

        (, uint256 performanceFee) = aggregationLayerVault.performanceFeeConfig();
        uint256 expectedPerformanceFee = yield * performanceFee / 1e18;

        Strategy memory strategyBeforeHarvest = aggregationLayerVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = aggregationLayerVault.totalAllocated();

        // harvest
        vm.prank(user1);
        aggregationLayerVault.harvest(address(eTST));

        assertEq(assetTST.balanceOf(feeRecipient), expectedPerformanceFee);
        assertEq(
            aggregationLayerVault.getStrategy(address(eTST)).allocated,
            strategyBeforeHarvest.allocated + yield - expectedPerformanceFee
        );
        assertEq(aggregationLayerVault.totalAllocated(), totalAllocatedBefore + yield - expectedPerformanceFee);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = aggregationLayerVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssetTST = aggregationLayerVault.convertToAssets(aggregationLayerVault.balanceOf(user1));

            vm.prank(user1);
            aggregationLayerVault.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(
                aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssetTST, 1
            );
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssetTST, 1);
        }

        // full withdraw of recipient fees
        {
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 assetTSTBalanceBefore = assetTST.balanceOf(feeRecipient);

            uint256 feeShares = aggregationLayerVault.balanceOf(feeRecipient);
            uint256 expectedAssets = aggregationLayerVault.convertToAssets(feeShares);
            vm.prank(feeRecipient);
            aggregationLayerVault.redeem(feeShares, feeRecipient, feeRecipient);

            assertApproxEqAbs(
                aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets, 1
            );
            assertEq(aggregationLayerVault.totalSupply(), 0);
            assertApproxEqAbs(assetTST.balanceOf(feeRecipient), assetTSTBalanceBefore + expectedAssets, 1);
        }
    }
}
