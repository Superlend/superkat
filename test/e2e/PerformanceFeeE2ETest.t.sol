// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationLayer
} from "../common/EulerAggregationLayerBase.t.sol";

contract PerformanceFeeE2ETest is EulerAggregationLayerBase {
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
            (, uint256 fee) = eulerAggregationLayer.performanceFeeConfig();
            assertEq(fee, 0);
        }

        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerAggregationLayer.setFeeRecipient(feeRecipient);
        eulerAggregationLayer.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        (address feeRecipientAddr, uint256 fee) = eulerAggregationLayer.performanceFeeConfig();
        assertEq(fee, newPerformanceFee);
        assertEq(feeRecipientAddr, feeRecipient);
    }

    function testHarvestWithFeeEnabled() public {
        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerAggregationLayer.setFeeRecipient(feeRecipient);
        eulerAggregationLayer.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = eulerAggregationLayer.balanceOf(user1);
            uint256 totalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(eulerAggregationLayer), amountToDeposit);
            eulerAggregationLayer.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(eulerAggregationLayer.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            IEulerAggregationLayer.Strategy memory strategyBefore = eulerAggregationLayer.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), strategyBefore.allocated);

            uint256 expectedStrategyCash = eulerAggregationLayer.totalAssetsAllocatable()
                * strategyBefore.allocationPoints / eulerAggregationLayer.totalAllocationPoints();

            vm.prank(user1);
            address[] memory strategiesToRebalance = new address[](1);
            strategiesToRebalance[0] = address(eTST);
            rebalancer.executeRebalance(address(eulerAggregationLayer), strategiesToRebalance);

            assertEq(eulerAggregationLayer.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationLayer))), expectedStrategyCash);
            assertEq((eulerAggregationLayer.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationLayer));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerAggregationLayer));
        }

        (, uint256 performanceFee) = eulerAggregationLayer.performanceFeeConfig();
        uint256 expectedPerformanceFee = yield * performanceFee / 1e18;

        IEulerAggregationLayer.Strategy memory strategyBeforeHarvest = eulerAggregationLayer.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerAggregationLayer.totalAllocated();

        // harvest
        vm.prank(user1);
        eulerAggregationLayer.harvest();

        assertEq(assetTST.balanceOf(feeRecipient), expectedPerformanceFee);
        assertEq(
            eulerAggregationLayer.getStrategy(address(eTST)).allocated,
            strategyBeforeHarvest.allocated + yield - expectedPerformanceFee
        );
        assertEq(eulerAggregationLayer.totalAllocated(), totalAllocatedBefore + yield - expectedPerformanceFee);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationLayer.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssetTST = eulerAggregationLayer.convertToAssets(eulerAggregationLayer.balanceOf(user1));

            vm.prank(user1);
            eulerAggregationLayer.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(
                eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssetTST, 1
            );
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssetTST, 1);
        }

        // full withdraw of recipient fees
        {
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 assetTSTBalanceBefore = assetTST.balanceOf(feeRecipient);

            uint256 feeShares = eulerAggregationLayer.balanceOf(feeRecipient);
            uint256 expectedAssets = eulerAggregationLayer.convertToAssets(feeShares);
            vm.prank(feeRecipient);
            eulerAggregationLayer.redeem(feeShares, feeRecipient, feeRecipient);

            assertApproxEqAbs(
                eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets, 1
            );
            assertEq(eulerAggregationLayer.totalSupply(), 0);
            assertApproxEqAbs(assetTST.balanceOf(feeRecipient), assetTSTBalanceBefore + expectedAssets, 1);
        }
    }
}
