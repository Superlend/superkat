// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/EulerEarnBase.t.sol";
import {TrackingRewardStreams} from "reward-streams/TrackingRewardStreams.sol";

contract StrategyRewardsE2ETest is EulerEarnBase {
    uint256 user1InitialBalance = 100000e18;

    IEVault nonActiveStrategy;

    function setUp() public virtual override {
        // deploy EVK base setup with real balancerTracker instance
        admin = vm.addr(1000);
        feeReceiver = makeAddr("feeReceiver");
        protocolFeeReceiver = makeAddr("protocolFeeReceiver");
        factory = new GenericFactory(admin);

        evc = new EthereumVaultConnector();
        protocolConfig = new ProtocolConfig(admin, protocolFeeReceiver);
        balanceTracker = address(new TrackingRewardStreams(address(evc), 2 weeks));
        oracle = new MockPriceOracle();
        unitOfAccount = address(1);
        permit2 = deployPermit2();
        sequenceRegistry = address(new SequenceRegistry());
        integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, balanceTracker, permit2);

        initializeModule = address(new InitializeOverride(integrations));
        tokenModule = address(new TokenOverride(integrations));
        vaultModule = address(new VaultOverride(integrations));
        borrowingModule = address(new BorrowingOverride(integrations));
        liquidationModule = address(new LiquidationOverride(integrations));
        riskManagerModule = address(new RiskManagerOverride(integrations));
        balanceForwarderModule = address(new BalanceForwarderOverride(integrations));
        governanceModule = address(new GovernanceOverride(integrations));

        modules = Dispatch.DeployedModules({
            initialize: initializeModule,
            token: tokenModule,
            vault: vaultModule,
            borrowing: borrowingModule,
            liquidation: liquidationModule,
            riskManager: riskManagerModule,
            balanceForwarder: balanceForwarderModule,
            governance: governanceModule
        });

        address evaultImpl = address(new EVault(integrations, modules));

        vm.prank(admin);
        factory.setImplementation(evaultImpl);

        assetTST = new TestERC20("Test Token", "TST", 18, false);

        eTST = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTST.setHookConfig(address(0), 0);
        eTST.setInterestRateModel(address(new IRMTestDefault()));
        eTST.setMaxLiquidationDiscount(0.2e4);
        eTST.setFeeReceiver(feeReceiver);

        // deploy euler earn

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");
        manager = makeAddr("Manager");

        vm.startPrank(deployer);
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

        vm.label(address(eulerEulerEarnVaultFactory), "eulerEulerEarnVaultFactory");
        vm.label(address(eulerEulerEarnVault), "eulerEulerEarnVault");
        vm.label(eulerEulerEarnVault.rewardsModule(), "rewardsModule");
        vm.label(eulerEulerEarnVault.hooksModule(), "hooksModule");
        vm.label(eulerEulerEarnVault.feeModule(), "feeModule");
        vm.label(eulerEulerEarnVault.strategyModule(), "strategyModule");
        vm.label(address(assetTST), "assetTST");
        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

        nonActiveStrategy = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
    }

    function testBalanceForwarderrAddress_Integrity() public view {
        assertEq(eulerEulerEarnVault.balanceTrackerAddress(), balanceTracker);
    }

    function testOptInStrategyRewards() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerEulerEarnVault.optInStrategyRewards(address(nonActiveStrategy));

        vm.expectEmit();
        emit EventsLib.OptInStrategyRewards(address(eTST));
        vm.prank(manager);
        eulerEulerEarnVault.optInStrategyRewards(address(eTST));

        assertTrue(eTST.balanceForwarderEnabled(address(eulerEulerEarnVault)));
    }

    function testOptOutStrategyRewards() public {
        vm.prank(manager);
        eulerEulerEarnVault.optInStrategyRewards(address(eTST));
        assertTrue(eTST.balanceForwarderEnabled(address(eulerEulerEarnVault)));

        vm.prank(manager);
        eulerEulerEarnVault.optOutStrategyRewards(address(eTST));

        assertFalse(eTST.balanceForwarderEnabled(address(eulerEulerEarnVault)));
    }

    function testEnableRewardForStrategy() public {
        vm.prank(manager);
        eulerEulerEarnVault.optInStrategyRewards(address(eTST));

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerEulerEarnVault.enableRewardForStrategy(address(nonActiveStrategy), address(assetTST));

        vm.expectEmit();
        emit EventsLib.EnableRewardForStrategy(address(eTST), address(assetTST));
        vm.prank(manager);
        eulerEulerEarnVault.enableRewardForStrategy(address(eTST), address(assetTST));
    }

    function testDisableRewardForStrategy() public {
        vm.prank(manager);
        eulerEulerEarnVault.optInStrategyRewards(address(eTST));

        vm.prank(manager);
        eulerEulerEarnVault.enableRewardForStrategy(address(eTST), address(assetTST));

        vm.prank(manager);
        eulerEulerEarnVault.disableRewardForStrategy(address(nonActiveStrategy), address(assetTST), true);

        vm.expectEmit();
        emit EventsLib.DisableRewardForStrategy(address(eTST), address(assetTST), true);
        vm.prank(manager);
        eulerEulerEarnVault.disableRewardForStrategy(address(eTST), address(assetTST), true);
    }

    function testClaimStrategyReward() public {
        vm.prank(manager);
        eulerEulerEarnVault.optInStrategyRewards(address(eTST));

        vm.prank(manager);
        eulerEulerEarnVault.enableRewardForStrategy(address(eTST), address(assetTST));

        vm.expectEmit();
        emit EventsLib.ClaimStrategyReward(address(eTST), address(assetTST), manager, true);
        vm.prank(manager);
        eulerEulerEarnVault.claimStrategyReward(address(eTST), address(assetTST), manager, true);
    }
}
