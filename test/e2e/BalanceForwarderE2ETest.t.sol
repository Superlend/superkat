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
import {TrackingRewardStreams} from "reward-streams/TrackingRewardStreams.sol";

contract BalanceForwarderE2ETest is FourSixTwoSixAggBase {
    uint256 user1InitialBalance = 100000e18;

    address trackingReward;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(deployer);
        trackingReward = address(new TrackingRewardStreams(address(evc), 2 weeks));

        fourSixTwoSixAgg = new FourSixTwoSixAgg(
            evc,
            trackingReward,
            address(assetTST),
            "assetTST_Agg",
            "assetTST_Agg",
            CASH_RESERVE_ALLOCATION_POINTS,
            new address[](0),
            new uint256[](0)
        );

        // grant admin roles to deployer
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE_ADMIN_ROLE(), deployer);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.PERFORMANCE_FEE_MANAGER_ROLE_ADMIN_ROLE(), deployer);

        // grant roles to manager
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.ALLOCATION_ADJUSTER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.WITHDRAW_QUEUE_REORDERER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_ADDER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.STRATEGY_REMOVER_ROLE(), manager);
        fourSixTwoSixAgg.grantRole(fourSixTwoSixAgg.PERFORMANCE_FEE_MANAGER_ROLE(), manager);
        vm.stopPrank();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
        assetTST.mint(user1, user1InitialBalance);

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(address(fourSixTwoSixAgg.balanceTracker()), trackingReward);
    }

    function testEnableBalanceForwarder() public {
        vm.prank(user1);
        fourSixTwoSixAgg.enableBalanceForwarder();

        assertTrue(fourSixTwoSixAgg.balanceForwarderEnabled(user1));
        assertEq(
            TrackingRewardStreams(trackingReward).balanceOf(user1, address(fourSixTwoSixAgg)),
            fourSixTwoSixAgg.balanceOf(user1)
        );
    }

    function testDisableBalanceForwarder() public {
        vm.prank(user1);
        fourSixTwoSixAgg.enableBalanceForwarder();

        assertTrue(fourSixTwoSixAgg.balanceForwarderEnabled(user1));

        vm.prank(user1);
        fourSixTwoSixAgg.disableBalanceForwarder();

        assertFalse(fourSixTwoSixAgg.balanceForwarderEnabled(user1));
        assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(fourSixTwoSixAgg)), 0);
    }

    function testHookWhenReceiverEnabled() public {
        vm.prank(user1);
        fourSixTwoSixAgg.enableBalanceForwarder();

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(fourSixTwoSixAgg)),
                fourSixTwoSixAgg.balanceOf(user1)
            );
        }
    }

    function testHookWhenSenderEnabled() public {
        vm.prank(user1);
        fourSixTwoSixAgg.enableBalanceForwarder();

        // deposit into aggregator
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(fourSixTwoSixAgg)),
                fourSixTwoSixAgg.balanceOf(user1)
            );
        }

        {
            uint256 amountToWithdraw = fourSixTwoSixAgg.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = fourSixTwoSixAgg.totalAssetsDeposited();
            uint256 aggregatorTotalSupplyBefore = fourSixTwoSixAgg.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            fourSixTwoSixAgg.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(fourSixTwoSixAgg)), 0);
            assertEq(fourSixTwoSixAgg.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(fourSixTwoSixAgg.totalSupply(), aggregatorTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + fourSixTwoSixAgg.convertToAssets(amountToWithdraw)
            );
            assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(fourSixTwoSixAgg)), 0);
        }
    }
}
