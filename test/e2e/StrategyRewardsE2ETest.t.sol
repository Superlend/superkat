// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../common/YieldAggregatorBase.t.sol";
import {TrackingRewardStreams} from "reward-streams/src/TrackingRewardStreams.sol";

contract StrategyRewardsE2ETest is YieldAggregatorBase {
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

        // deploy yield aggregator

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");
        manager = makeAddr("Manager");

        vm.startPrank(deployer);
        yieldAggregatorVaultModule = new YieldAggregatorVault(address(evc));
        rewardsModule = new Rewards(address(evc));
        hooksModule = new Hooks(address(evc));
        feeModuleModule = new Fee(address(evc));
        strategyModuleModule = new Strategy(address(evc));
        withdrawalQueueModuleModule = new WithdrawalQueue(address(evc));

        YieldAggregatorFactory.FactoryParams memory factoryParams = YieldAggregatorFactory.FactoryParams({
            owner: deployer,
            evc: address(evc),
            balanceTracker: address(0),
            yieldAggregatorVaultModule: address(yieldAggregatorVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModuleModule),
            strategyModule: address(strategyModuleModule),
            withdrawalQueueModule: address(withdrawalQueueModuleModule)
        });
        eulerYieldAggregatorVaultFactory = new YieldAggregatorFactory(factoryParams);
        eulerYieldAggregatorVault = YieldAggregator(
            eulerYieldAggregatorVaultFactory.deployYieldAggregator(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );

        // grant admin roles to deployer
        eulerYieldAggregatorVault.grantRole(ConstantsLib.GUARDIAN_ADMIN, deployer);
        eulerYieldAggregatorVault.grantRole(ConstantsLib.STRATEGY_OPERATOR_ADMIN, deployer);
        eulerYieldAggregatorVault.grantRole(ConstantsLib.YIELD_AGGREGATOR_MANAGER_ADMIN, deployer);
        eulerYieldAggregatorVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN, deployer);

        // grant roles to manager
        eulerYieldAggregatorVault.grantRole(ConstantsLib.GUARDIAN, manager);
        eulerYieldAggregatorVault.grantRole(ConstantsLib.STRATEGY_OPERATOR, manager);
        eulerYieldAggregatorVault.grantRole(ConstantsLib.YIELD_AGGREGATOR_MANAGER, manager);
        eulerYieldAggregatorVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER, manager);

        vm.stopPrank();

        vm.label(address(eulerYieldAggregatorVaultFactory), "eulerYieldAggregatorVaultFactory");
        vm.label(address(eulerYieldAggregatorVault), "eulerYieldAggregatorVault");
        vm.label(eulerYieldAggregatorVault.rewardsModule(), "rewardsModule");
        vm.label(eulerYieldAggregatorVault.hooksModule(), "hooksModule");
        vm.label(eulerYieldAggregatorVault.feeModule(), "feeModule");
        vm.label(eulerYieldAggregatorVault.strategyModule(), "strategyModule");
        vm.label(address(assetTST), "assetTST");
        uint256 initialStrategyAllocationPoints = 500e18;
        _addStrategy(manager, address(eTST), initialStrategyAllocationPoints);

        assetTST.mint(user1, user1InitialBalance);

        nonActiveStrategy = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
    }

    function testOptInStrategyRewards() public {
        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerYieldAggregatorVault.optInStrategyRewards(address(nonActiveStrategy));

        vm.expectEmit();
        emit EventsLib.OptInStrategyRewards(address(eTST));
        vm.prank(manager);
        eulerYieldAggregatorVault.optInStrategyRewards(address(eTST));

        assertTrue(eTST.balanceForwarderEnabled(address(eulerYieldAggregatorVault)));
    }

    function testOptOutStrategyRewards() public {
        vm.prank(manager);
        eulerYieldAggregatorVault.optInStrategyRewards(address(eTST));
        assertTrue(eTST.balanceForwarderEnabled(address(eulerYieldAggregatorVault)));

        vm.prank(manager);
        eulerYieldAggregatorVault.optOutStrategyRewards(address(eTST));

        assertFalse(eTST.balanceForwarderEnabled(address(eulerYieldAggregatorVault)));
    }

    function testEnableRewardForStrategy() public {
        vm.prank(manager);
        eulerYieldAggregatorVault.optInStrategyRewards(address(eTST));

        vm.prank(manager);
        vm.expectRevert(ErrorsLib.StrategyShouldBeActive.selector);
        eulerYieldAggregatorVault.enableRewardForStrategy(address(nonActiveStrategy), address(assetTST));

        vm.expectEmit();
        emit EventsLib.EnableRewardForStrategy(address(eTST), address(assetTST));
        vm.prank(manager);
        eulerYieldAggregatorVault.enableRewardForStrategy(address(eTST), address(assetTST));
    }

    function testDisableRewardForStrategy() public {
        vm.prank(manager);
        eulerYieldAggregatorVault.optInStrategyRewards(address(eTST));

        vm.prank(manager);
        eulerYieldAggregatorVault.enableRewardForStrategy(address(eTST), address(assetTST));

        vm.prank(manager);
        eulerYieldAggregatorVault.disableRewardForStrategy(address(nonActiveStrategy), address(assetTST), true);

        vm.expectEmit();
        emit EventsLib.DisableRewardForStrategy(address(eTST), address(assetTST), true);
        vm.prank(manager);
        eulerYieldAggregatorVault.disableRewardForStrategy(address(eTST), address(assetTST), true);
    }

    function testClaimStrategyReward() public {
        vm.prank(manager);
        eulerYieldAggregatorVault.optInStrategyRewards(address(eTST));

        vm.prank(manager);
        eulerYieldAggregatorVault.enableRewardForStrategy(address(eTST), address(assetTST));

        vm.expectEmit();
        emit EventsLib.ClaimStrategyReward(address(eTST), address(assetTST), manager, true);
        vm.prank(manager);
        eulerYieldAggregatorVault.claimStrategyReward(address(eTST), address(assetTST), manager, true);
    }
}
