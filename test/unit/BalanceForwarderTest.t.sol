// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";

contract BalanceForwarderTest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;

    EulerEarn eulerEulerEarnVaultNoTracker;

    function setUp() public virtual override {
        super.setUp();

        eulerEulerEarnVaultNoTracker = EulerEarn(
            eulerEulerEarnVaultFactory.deployEulerEarn(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS, 2 weeks
            )
        );

        vm.startPrank(deployer);
        balanceTracker = address(new MockBalanceTracker());
        integrationsParams = Shared.IntegrationsParams({
            evc: address(evc),
            balanceTracker: balanceTracker,
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
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS, 2 weeks
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
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(eulerEulerEarnVault.balanceTrackerAddress(), balanceTracker);
    }

    function testEnableBalanceForwarder() public {
        vm.expectEmit();
        emit EventsLib.EnableBalanceForwarder(user1);
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();

        assertTrue(eulerEulerEarnVault.balanceForwarderEnabled(user1));
        assertEq(MockBalanceTracker(balanceTracker).numCalls(), 1);
        assertEq(MockBalanceTracker(balanceTracker).calls(user1, 0, false), 1);
    }

    function test_EnableBalanceForwarder_AlreadyEnabledOk() public {
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();

        assertTrue(eulerEulerEarnVault.balanceForwarderEnabled(user1));
    }

    function testEnableBalanceForwarderEulerEarnRewardsNotSupported() public {
        vm.expectRevert(ErrorsLib.EulerEarnRewardsNotSupported.selector);
        vm.prank(user1);
        eulerEulerEarnVaultNoTracker.enableBalanceForwarder();
    }

    function testDisableBalanceForwarder() public {
        vm.prank(user1);
        eulerEulerEarnVault.enableBalanceForwarder();

        vm.expectEmit();
        emit EventsLib.DisableBalanceForwarder(user1);
        vm.prank(user1);
        eulerEulerEarnVault.disableBalanceForwarder();

        assertFalse(eulerEulerEarnVault.balanceForwarderEnabled(user1));
        assertEq(MockBalanceTracker(balanceTracker).numCalls(), 2);
        assertEq(MockBalanceTracker(balanceTracker).calls(user1, 0, false), 2);
    }

    function testDisableBalanceForwarder_AlreadyDisabledOk() public {
        assertFalse(eulerEulerEarnVault.balanceForwarderEnabled(user1));
        vm.prank(user1);
        eulerEulerEarnVault.disableBalanceForwarder();

        assertFalse(eulerEulerEarnVault.balanceForwarderEnabled(user1));
    }

    function testDisableBalanceForwarder_RevertsWhen_NoBalanceTracker() public {
        vm.expectRevert(ErrorsLib.EulerEarnRewardsNotSupported.selector);
        vm.prank(user1);
        eulerEulerEarnVaultNoTracker.disableBalanceForwarder();
    }
}
