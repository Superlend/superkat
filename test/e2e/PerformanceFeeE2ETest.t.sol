// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    FourSixTwoSixAggBase,
    FourSixTwoSixAgg,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20
} from "../common/FourSixTwoSixAggBase.t.sol";

contract PerformanceFeeE2ETest is FourSixTwoSixAggBase {
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
        assertEq(fourSixTwoSixAgg.performanceFee(), 0);

        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        fourSixTwoSixAgg.setFeeRecipient(feeRecipient);
        fourSixTwoSixAgg.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        assertEq(fourSixTwoSixAgg.performanceFee(), newPerformanceFee);
        assertEq(fourSixTwoSixAgg.feeRecipient(), feeRecipient);
    }

    function testHarvestWithFeeEnabled() public {
        uint256 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        fourSixTwoSixAgg.setFeeRecipient(feeRecipient);
        fourSixTwoSixAgg.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;

        // deposit into aggregator
        {
            uint256 balanceBefore = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

            vm.startPrank(user1);
            assetTST.approve(address(fourSixTwoSixAgg), amountToDeposit);
            fourSixTwoSixAgg.deposit(amountToDeposit, user1);
            vm.stopPrank();

            assertEq(fourSixTwoSixAgg.balanceOf(user1), balanceBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalSupply(), totalSupplyBefore + amountToDeposit);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore + amountToDeposit);
            assertEq(assetTST.balanceOf(user1), userAssetBalanceBefore - amountToDeposit);
        }

        // rebalance into strategy
        vm.warp(block.timestamp + 86400);
        {
            FourSixTwoSixAgg.Strategy memory strategyBefore = fourSixTwoSixAgg.getStrategy(address(eTST));

            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), strategyBefore.allocated);

            uint256 expectedStrategyCash = fourSixTwoSixAgg.totalAssetsAllocatable() * strategyBefore.allocationPoints
                / fourSixTwoSixAgg.totalAllocationPoints();

            vm.prank(user1);
            fourSixTwoSixAgg.rebalance(address(eTST));

            assertEq(fourSixTwoSixAgg.totalAllocated(), expectedStrategyCash);
            assertEq(eTST.convertToAssets(eTST.balanceOf(address(fourSixTwoSixAgg))), expectedStrategyCash);
            assertEq((fourSixTwoSixAgg.getStrategy(address(eTST))).allocated, expectedStrategyCash);
        }

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(fourSixTwoSixAgg));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(fourSixTwoSixAgg));
        }

        uint256 expectedPerformanceFee = yield * fourSixTwoSixAgg.performanceFee() / 1e18;
        uint256 expectedPerformanceFeeShares = fourSixTwoSixAgg.convertToShares(expectedPerformanceFee);

        // harvest
        vm.prank(user1);
        fourSixTwoSixAgg.harvest(address(eTST));

        assertEq(fourSixTwoSixAgg.balanceOf(feeRecipient), expectedPerformanceFeeShares);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssetTST = fourSixTwoSixAgg.convertToAssets(fourSixTwoSixAgg.balanceOf(user1));

            vm.prank(user1);
            fourSixTwoSixAgg.redeem(amountToWithdraw, user1, user1);

            // all yield is distributed
            // assertApproxEqAbs(eTST.balanceOf(address(fourSixTwoSixAgg)), expectePerformanceFeeAssets, 1);
            assertApproxEqAbs(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssetTST, 1);
            assertEq(fourSixTwoSixAgg.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssetTST, 1);
        }

        // full withdraw of recipient fees
        {
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 assetTSTBalanceBefore = assetTST.balanceOf(feeRecipient);

            uint256 feeShares = fourSixTwoSixAgg.balanceOf(feeRecipient);
            uint256 expectedAssets = fourSixTwoSixAgg.convertToAssets(feeShares);
            vm.prank(feeRecipient);
            fourSixTwoSixAgg.redeem(feeShares, feeRecipient, feeRecipient);

            // all yield is distributed
            // assertApproxEqAbs(eTST.balanceOf(address(fourSixTwoSixAgg)), 0, 1);
            assertApproxEqAbs(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets, 1);
            assertEq(fourSixTwoSixAgg.totalSupply(), 0);
            assertApproxEqAbs(assetTST.balanceOf(feeRecipient), assetTSTBalanceBefore + expectedAssets, 1);
        }
    }
}
