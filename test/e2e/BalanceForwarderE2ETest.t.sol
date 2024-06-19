// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {TrackingRewardStreams} from "reward-streams/TrackingRewardStreams.sol";
import {
    AggregationLayerVaultBase,
    AggregationLayerVault,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    AggregationLayerVaultFactory,
    Rewards
} from "../common/AggregationLayerVaultBase.t.sol";

contract BalanceForwarderE2ETest is AggregationLayerVaultBase {
    uint256 user1InitialBalance = 100000e18;

    address trackingReward;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(deployer);
        trackingReward = address(new TrackingRewardStreams(address(evc), 2 weeks));

        AggregationLayerVaultFactory.FactoryParams memory factoryParams = AggregationLayerVaultFactory.FactoryParams({
            evc: address(evc),
            balanceTracker: trackingReward,
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            allocationPointsModuleImpl: address(allocationPointsModuleImpl),
            rebalancer: address(rebalancer),
            withdrawalQueueImpl: address(withdrawalQueueImpl)
        });
        aggregationLayerVaultFactory = new AggregationLayerVaultFactory(factoryParams);
        aggregationLayerVault = AggregationLayerVault(
            aggregationLayerVaultFactory.deployEulerAggregationLayer(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );

        // grant admin roles to deployer
        aggregationLayerVault.grantRole(aggregationLayerVault.ALLOCATIONS_MANAGER_ADMIN(), deployer);
        // aggregationLayerVault.grantRole(aggregationLayerVault.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_ADDER_ADMIN(), deployer);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_REMOVER_ADMIN(), deployer);
        aggregationLayerVault.grantRole(aggregationLayerVault.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer);

        // grant roles to manager
        aggregationLayerVault.grantRole(aggregationLayerVault.ALLOCATIONS_MANAGER(), manager);
        // aggregationLayerVault.grantRole(aggregationLayerVault.WITHDRAW_QUEUE_MANAGER(), manager);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_ADDER(), manager);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_REMOVER(), manager);
        aggregationLayerVault.grantRole(aggregationLayerVault.AGGREGATION_VAULT_MANAGER(), manager);
        vm.stopPrank();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
        assetTST.mint(user1, user1InitialBalance);

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(aggregationLayerVault.balanceTrackerAddress(), trackingReward);
    }

    function testEnableBalanceForwarder() public {
        vm.prank(user1);
        aggregationLayerVault.enableBalanceForwarder();

        assertTrue(aggregationLayerVault.balanceForwarderEnabled(user1));
        assertEq(
            TrackingRewardStreams(trackingReward).balanceOf(user1, address(aggregationLayerVault)),
            aggregationLayerVault.balanceOf(user1)
        );
    }

    function testDisableBalanceForwarder() public {
        vm.prank(user1);
        aggregationLayerVault.enableBalanceForwarder();

        assertTrue(aggregationLayerVault.balanceForwarderEnabled(user1));

        vm.prank(user1);
        aggregationLayerVault.disableBalanceForwarder();

        assertFalse(aggregationLayerVault.balanceForwarderEnabled(user1));
        assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(aggregationLayerVault)), 0);
    }

    function testHookWhenReceiverEnabled() public {
        vm.prank(user1);
        aggregationLayerVault.enableBalanceForwarder();

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(aggregationLayerVault)),
                aggregationLayerVault.balanceOf(user1)
            );
        }
    }

    function testHookWhenSenderEnabled() public {
        vm.prank(user1);
        aggregationLayerVault.enableBalanceForwarder();

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(aggregationLayerVault)),
                aggregationLayerVault.balanceOf(user1)
            );
        }

        {
            uint256 amountToWithdraw = aggregationLayerVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = aggregationLayerVault.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = aggregationLayerVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            aggregationLayerVault.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(aggregationLayerVault)), 0);
            assertEq(aggregationLayerVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(aggregationLayerVault.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + aggregationLayerVault.convertToAssets(amountToWithdraw)
            );
            assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(aggregationLayerVault)), 0);
        }
    }
}
