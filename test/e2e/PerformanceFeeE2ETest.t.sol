// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract PerformanceFeeE2ETest is EulerEarnBase {
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
        (address feeRecipientAddr, uint256 fee) = eulerEulerEarnVault.performanceFeeConfig();
        assertEq(fee, 0);
        assertEq(feeRecipientAddr, address(0));

        uint96 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerEulerEarnVault.setFeeRecipient(feeRecipient);
        eulerEulerEarnVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        (feeRecipientAddr, fee) = eulerEulerEarnVault.performanceFeeConfig();
        assertEq(fee, newPerformanceFee);
        assertEq(feeRecipientAddr, feeRecipient);
    }

    function testHarvestWithFeeEnabled() public {
        uint96 newPerformanceFee = 3e17;

        vm.startPrank(manager);
        eulerEulerEarnVault.setFeeRecipient(feeRecipient);
        eulerEulerEarnVault.setPerformanceFee(newPerformanceFee);
        vm.stopPrank();

        uint256 amountToDeposit = 10000e18;

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

        vm.warp(block.timestamp + 86400);
        // mock an increase of strategy balance by 10%
        uint256 yield;
        {
            uint256 aggrCurrentStrategyShareBalance = eTST.balanceOf(address(eulerEulerEarnVault));
            uint256 aggrCurrentStrategyUnderlyingBalance = eTST.convertToAssets(aggrCurrentStrategyShareBalance);
            uint256 aggrNewStrategyUnderlyingBalance = aggrCurrentStrategyUnderlyingBalance * 11e17 / 1e18;
            yield = aggrNewStrategyUnderlyingBalance - aggrCurrentStrategyUnderlyingBalance;
            assetTST.mint(address(eTST), yield);
            eTST.skim(type(uint256).max, address(eulerEulerEarnVault));
        }

        (, uint256 performanceFee) = eulerEulerEarnVault.performanceFeeConfig();
        uint256 expectedPerformanceFeeAssets = yield * performanceFee / 1e18;
        uint256 expectedPerformanceFeeShares = eulerEulerEarnVault.previewDeposit(expectedPerformanceFeeAssets);

        IEulerEarn.Strategy memory strategyBeforeHarvest = eulerEulerEarnVault.getStrategy(address(eTST));
        uint256 totalAllocatedBefore = eulerEulerEarnVault.totalAllocated();

        uint256 previewedAssets = eulerEulerEarnVault.previewRedeem(eulerEulerEarnVault.balanceOf(user1));

        // harvest
        vm.prank(user1);
        eulerEulerEarnVault.harvest();

        assertGt(expectedPerformanceFeeShares, 0);
        assertEq(assetTST.balanceOf(feeRecipient), 0);
        assertEq(eulerEulerEarnVault.balanceOf(feeRecipient), expectedPerformanceFeeShares);
        assertEq(eulerEulerEarnVault.getStrategy(address(eTST)).allocated, strategyBeforeHarvest.allocated + yield);
        assertEq(eulerEulerEarnVault.totalAllocated(), totalAllocatedBefore + yield);

        // full withdraw, will have to withdraw from strategy as cash reserve is not enough
        {
            uint256 amountToWithdraw = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);
            uint256 expectedAssetTST = eulerEulerEarnVault.convertToAssets(eulerEulerEarnVault.balanceOf(user1));

            vm.prank(user1);
            uint256 withdrawnAssets = eulerEulerEarnVault.redeem(amountToWithdraw, user1, user1);

            assertApproxEqAbs(
                eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssetTST, 1
            );
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToWithdraw);
            assertApproxEqAbs(assetTST.balanceOf(user1), user1AssetTSTBalanceBefore + expectedAssetTST, 1);
            assertEq(withdrawnAssets, previewedAssets);
        }

        // full redemption of recipient fees
        {
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 assetTSTBalanceBefore = assetTST.balanceOf(feeRecipient);

            uint256 feeShares = eulerEulerEarnVault.balanceOf(feeRecipient);
            uint256 expectedAssets = eulerEulerEarnVault.convertToAssets(feeShares);
            assertGt(expectedAssets, 0);

            vm.prank(feeRecipient);
            eulerEulerEarnVault.redeem(feeShares, feeRecipient, feeRecipient);

            assertApproxEqAbs(
                eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - expectedAssets, 1
            );
            assertEq(eulerEulerEarnVault.totalSupply(), 0);
            assertApproxEqAbs(assetTST.balanceOf(feeRecipient), assetTSTBalanceBefore + expectedAssets, 1);
        }
    }
}
