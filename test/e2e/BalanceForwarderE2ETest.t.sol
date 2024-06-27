// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {TrackingRewardStreams} from "reward-streams/TrackingRewardStreams.sol";
import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    console2,
    EVault,
    IEVault,
    IRMTestDefault,
    TestERC20,
    EulerAggregationLayerFactory,
    Rewards
} from "../common/EulerAggregationLayerBase.t.sol";

contract BalanceForwarderE2ETest is EulerAggregationLayerBase {
    uint256 user1InitialBalance = 100000e18;

    address trackingReward;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(deployer);
        trackingReward = address(new TrackingRewardStreams(address(evc), 2 weeks));

        EulerAggregationLayerFactory.FactoryParams memory factoryParams = EulerAggregationLayerFactory.FactoryParams({
            evc: address(evc),
            balanceTracker: trackingReward,
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            allocationPointsModuleImpl: address(allocationPointsModuleImpl),
            rebalancer: address(rebalancer),
            withdrawalQueueImpl: address(withdrawalQueueImpl)
        });
        eulerAggregationLayerFactory = new EulerAggregationLayerFactory(factoryParams);
        eulerAggregationLayer = EulerAggregationLayer(
            eulerAggregationLayerFactory.deployEulerAggregationLayer(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );

        // grant admin roles to deployer
        eulerAggregationLayer.grantRole(eulerAggregationLayer.ALLOCATIONS_MANAGER_ADMIN(), deployer);
        // eulerAggregationLayer.grantRole(eulerAggregationLayer.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_ADDER_ADMIN(), deployer);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_REMOVER_ADMIN(), deployer);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer);

        // grant roles to manager
        eulerAggregationLayer.grantRole(eulerAggregationLayer.ALLOCATIONS_MANAGER(), manager);
        // eulerAggregationLayer.grantRole(eulerAggregationLayer.WITHDRAW_QUEUE_MANAGER(), manager);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_ADDER(), manager);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_REMOVER(), manager);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.AGGREGATION_VAULT_MANAGER(), manager);
        vm.stopPrank();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
        assetTST.mint(user1, user1InitialBalance);

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(eulerAggregationLayer.balanceTrackerAddress(), trackingReward);
    }

    function testEnableBalanceForwarder() public {
        vm.prank(user1);
        eulerAggregationLayer.enableBalanceForwarder();

        assertTrue(eulerAggregationLayer.balanceForwarderEnabled(user1));
        assertEq(
            TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerAggregationLayer)),
            eulerAggregationLayer.balanceOf(user1)
        );
    }

    function testDisableBalanceForwarder() public {
        vm.prank(user1);
        eulerAggregationLayer.enableBalanceForwarder();

        assertTrue(eulerAggregationLayer.balanceForwarderEnabled(user1));

        vm.prank(user1);
        eulerAggregationLayer.disableBalanceForwarder();

        assertFalse(eulerAggregationLayer.balanceForwarderEnabled(user1));
        assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerAggregationLayer)), 0);
    }

    function testHookWhenReceiverEnabled() public {
        vm.prank(user1);
        eulerAggregationLayer.enableBalanceForwarder();

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerAggregationLayer)),
                eulerAggregationLayer.balanceOf(user1)
            );
        }
    }

    function testHookWhenSenderEnabled() public {
        vm.prank(user1);
        eulerAggregationLayer.enableBalanceForwarder();

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerAggregationLayer)),
                eulerAggregationLayer.balanceOf(user1)
            );
        }

        {
            uint256 amountToWithdraw = eulerAggregationLayer.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerAggregationLayer.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = eulerAggregationLayer.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerAggregationLayer.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerAggregationLayer)), 0);
            assertEq(eulerAggregationLayer.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerAggregationLayer.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerAggregationLayer.convertToAssets(amountToWithdraw)
            );
            assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerAggregationLayer)), 0);
        }
    }
}
