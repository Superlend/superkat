// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";
import {TrackingRewardStreams} from "reward-streams/src/TrackingRewardStreams.sol";

contract BalanceForwarderE2ETest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;

    address trackingReward;

    function setUp() public virtual override {
        super.setUp();

        vm.startPrank(deployer);
        trackingReward = address(new TrackingRewardStreams(address(evc), 2 weeks));

        integrationsParams = Shared.IntegrationsParams({
            evc: address(evc),
            balanceTracker: trackingReward,
            permit2: permit2,
            isHarvestCoolDownCheckOn: true
        });

        eulerEarnVaultModule = new EulerEarnVault(integrationsParams);
        rewardsModule = new Rewards(integrationsParams);
        hooksModule = new Hooks(integrationsParams);
        feeModule = new Fee(integrationsParams);
        strategyModule = new Strategy(integrationsParams);
        withdrawalQueueModule = new WithdrawalQueue(integrationsParams);

        deploymentParams = IEulerEarn.DeploymentParams({
            eulerEarnVaultModule: address(eulerEarnVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModule),
            strategyModule: address(strategyModule),
            withdrawalQueueModule: address(withdrawalQueueModule)
        });
        eulerEarnImpl = address(new EulerEarn(integrationsParams, deploymentParams));

        eulerEulerEarnVaultFactory = new EulerEarnFactory(eulerEarnImpl);

        eulerEulerEarnVault = EulerEarn(
            eulerEulerEarnVaultFactory.deployEulerEarn(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );

        // grant admin roles to deployer
        eulerEulerEarnVault.grantRole(ConstantsLib.GUARDIAN_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.STRATEGY_OPERATOR_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.EULER_EARN_MANAGER_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN, deployer);
        eulerEulerEarnVault.grantRole(ConstantsLib.REBALANCER_ADMIN, deployer);

        // grant roles to manager
        eulerEulerEarnVault.grantRole(ConstantsLib.GUARDIAN, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.STRATEGY_OPERATOR, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.EULER_EARN_MANAGER, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.REBALANCER, manager);
        vm.stopPrank();

        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);
        assetTST.mint(user1, user1InitialBalance);

        // deposit into EulerEarn
        uint256 amountToDeposit = 10000e18;
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
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(eulerEulerEarnVault.balanceTrackerAddress(), trackingReward);
    }

    function testEnableBalanceForwarder() public {
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();

        assertTrue(eulerEulerEarnVault.balanceForwarderEnabled(user1));
        assertEq(
            TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerEulerEarnVault)),
            eulerEulerEarnVault.balanceOf(user1)
        );
    }

    function testDisableBalanceForwarder() public {
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();

        assertTrue(eulerEulerEarnVault.balanceForwarderEnabled(user1));

        vm.prank(user1);
        eulerEulerEarnVault.disableBalanceForwarder();

        assertFalse(eulerEulerEarnVault.balanceForwarderEnabled(user1));
        assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerEulerEarnVault)), 0);
    }

    function testHookWhenReceiverEnabled() public {
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();

        // deposit into EulerEarn
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerEulerEarnVault)),
                eulerEulerEarnVault.balanceOf(user1)
            );
        }
    }

    function testHookWhenSenderEnabled() public {
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();

        // deposit into EulerEarn
        uint256 amountToDeposit = 10000e18;
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

            assertEq(
                TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerEulerEarnVault)),
                eulerEulerEarnVault.balanceOf(user1)
            );
        }

        {
            uint256 amountToWithdraw = eulerEulerEarnVault.balanceOf(user1);
            uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
            uint256 eulerEarnTotalSupplyBefore = eulerEulerEarnVault.totalSupply();
            uint256 user1AssetTSTBalanceBefore = assetTST.balanceOf(user1);

            vm.prank(user1);
            eulerEulerEarnVault.redeem(amountToWithdraw, user1, user1);

            assertEq(eTST.balanceOf(address(eulerEulerEarnVault)), 0);
            assertEq(eulerEulerEarnVault.totalAssetsDeposited(), totalAssetsDepositedBefore - amountToWithdraw);
            assertEq(eulerEulerEarnVault.totalSupply(), eulerEarnTotalSupplyBefore - amountToWithdraw);
            assertEq(
                assetTST.balanceOf(user1),
                user1AssetTSTBalanceBefore + eulerEulerEarnVault.convertToAssets(amountToWithdraw)
            );
            assertEq(TrackingRewardStreams(trackingReward).balanceOf(user1, address(eulerEulerEarnVault)), 0);
        }
    }
}
