// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    IEulerAggregationVault
} from "../common/EulerAggregationVaultBase.t.sol";

contract PerformanceFeeE2ETest is EulerAggregationVaultBase {
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
        (address feeRecipientAddr, uint256 fee) = eulerAggregationVault.performanceFeeConfig();
        assertEq(fee, 0);
        assertEq(feeRecipientAddr, address(0));

        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerAggregationVault.setFeeRecipient(feeRecipient);
        eulerAggregationVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        (feeRecipientAddr, fee) = eulerAggregationVault.performanceFeeConfig();
        assertEq(fee, newPerformanceFee);
        assertEq(feeRecipientAddr, feeRecipient);
    }

    function testHarvestWithFeeEnabled() public {
        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerAggregationVault.setFeeRecipient(feeRecipient);
        eulerAggregationVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;

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
            rebalancer.executeRebalance(address(eulerAggregationVault), strategiesToRebalance);

            assertEq(eulerAggregationVault.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(eulerAggregationVault))), expectedStrategyCash);
            assertEq((eulerAggregationVault.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerAggregationVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerAggregationVault));
        }

        (, uint256 performanceFee) = eulerAggregationVault.performanceFeeConfig();
        uint256 expectedPerformanceFee = yield * performanceFee / 1e18;

        IEulerAggregationVault.Strategy memory strategyBeforeHarvest = eulerAggregationVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerAggregationVault.totalAllocated();

        // harvest
        vm.prank(user1);
        eulerAggregationVault.harvest();

        assertEq(assetTST.balanceOf(feeRecipient), expectedPerformanceFee);
        assertEq(
            eulerAggregationVault.getStrategy(address(eTST)).allocated,
            strategyBeforeHarvest.allocated + yield - expectedPerformanceFee
        );
        assertEq(eulerAggregationVault.totalAllocated(), totalAllocatedBefore + yield - expectedPerformanceFee);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerAggregationVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssetTST = eulerAggregationVault.convertToAssets(eulerAggregationVault.balanceOf(user1));

            vm.prank(user1);
            eulerAggregationVault.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(
                eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssetTST, 1
            );
            assertEq(eulerAggregationVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssetTST, 1);
        }

        // full withdraw of recipient fees
        {
            uint256 totalAssetsDepositedBefore = eulerAggregationVault.totalAssetsDeposited();
            uint256 assetTSTBalanceBefore = assetTST.balanceOf(feeRecipient);

            uint256 feeShares = eulerAggregationVault.balanceOf(feeRecipient);
            uint256 expectedAssets = eulerAggregationVault.convertToAssets(feeShares);
            vm.prank(feeRecipient);
            eulerAggregationVault.redeem(feeShares, feeRecipient, feeRecipient);

            assertApproxEqAbs(
                eulerAggregationVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets, 1
            );
            assertEq(eulerAggregationVault.totalSupply(), 0);
            assertApproxEqAbs(assetTST.balanceOf(feeRecipient), assetTSTBalanceBefore + expectedAssets, 1);
        }
    }
}
