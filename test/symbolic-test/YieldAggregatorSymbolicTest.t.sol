// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {
    YieldAggregatorBase,
    YieldAggregator,
    IEVault,
    TestERC20,
    IYieldAggregator,
    ConstantsLib,
    GenericFactory,
    EthereumVaultConnector,
    ProtocolConfig,
    MockBalanceTracker,
    MockPriceOracle,
    SequenceRegistry,
    Base,
    Initialize,
    Token,
    Vault,
    Borrowing,
    Liquidation,
    RiskManager,
    BalanceForwarder,
    Governance,
    Dispatch,
    EVault,
    IRMTestDefault,
    YieldAggregatorVault,
    Rewards,
    Hooks,
    Fee,
    Strategy,
    Rebalance,
    WithdrawalQueue,
    YieldAggregatorFactory
} from "../common/YieldAggregatorBase.t.sol";

contract YieldAggregatorSymbolicTest is YieldAggregatorBase, SymTest {
    function setUp() public override {
        admin = svm.createAddress("admin");
        vm.assume(admin != address(0));
        feeReceiver = svm.createAddress("feeReceiver");
        vm.assume(feeReceiver != address(0));
        protocolFeeReceiver = svm.createAddress("protocolFeeReceiver");
        vm.assume(protocolFeeReceiver != address(0));
        factory = new GenericFactory(admin);

        evc = new EthereumVaultConnector();
        protocolConfig = new ProtocolConfig(admin, protocolFeeReceiver);
        balanceTracker = address(new MockBalanceTracker());
        oracle = new MockPriceOracle();
        unitOfAccount = address(1);
        permit2 = deployPermit2();
        sequenceRegistry = address(new SequenceRegistry());
        integrations =
            Base.Integrations(address(evc), address(protocolConfig), sequenceRegistry, balanceTracker, permit2);

        initializeModule = address(new Initialize(integrations));
        tokenModule = address(new Token(integrations));
        vaultModule = address(new Vault(integrations));
        borrowingModule = address(new Borrowing(integrations));
        liquidationModule = address(new Liquidation(integrations));
        riskManagerModule = address(new RiskManager(integrations));
        balanceForwarderModule = address(new BalanceForwarder(integrations));
        governanceModule = address(new Governance(integrations));

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
        assetTST2 = new TestERC20("Test Token 2", "TST2", 18, false);

        eTST = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        eTST.setHookConfig(address(0), 0);
        eTST.setInterestRateModel(address(new IRMTestDefault()));
        eTST.setMaxLiquidationDiscount(0.2e4);
        eTST.setFeeReceiver(feeReceiver);

        eTST2 = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST2), address(oracle), unitOfAccount))
        );
        eTST2.setHookConfig(address(0), 0);
        eTST2.setInterestRateModel(address(new IRMTestDefault()));
        eTST2.setMaxLiquidationDiscount(0.2e4);
        eTST2.setFeeReceiver(feeReceiver);

        deployer = svm.createAddress("deployer");
        vm.assume(deployer != address(0));
        user1 = svm.createAddress("user1");
        vm.assume(user1 != address(0));
        user2 = svm.createAddress("user2");
        vm.assume(user2 != address(0));
        manager = svm.createAddress("manager");
        vm.assume(manager != address(0));

        vm.startPrank(deployer);
        yieldAggregatorVaultModule = new YieldAggregatorVault(address(evc));
        rewardsModule = new Rewards(address(evc));
        hooksModule = new Hooks(address(evc));
        feeModuleModule = new Fee(address(evc));
        strategyModuleModule = new Strategy(address(evc));
        rebalanceModuleModule = new Rebalance(address(evc));
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
            rebalanceModule: address(rebalanceModuleModule),
            withdrawalQueueModule: address(withdrawalQueueModuleModule)
        });
        eulerYieldAggregatorVaultFactory = new YieldAggregatorFactory(factoryParams);

        uint256 initialCashReservePointsAllocation = svm.createUint256("initialCashReservePointsAllocation");
        vm.assume(1 <= initialCashReservePointsAllocation && initialCashReservePointsAllocation <= type(uint120).max);

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
    }

    // Strategy module's functions
    function check_addStrategy() public {
        address strategyAddr = address(
            IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            )
        );
        uint256 allocationPoints = svm.createUint256("allocationPoints");
        vm.assume(allocationPoints <= type(uint120).max);

        uint256 totalAllocationPointsBefore = eulerYieldAggregatorVault.totalAllocationPoints();

        vm.prank(manager);
        eulerYieldAggregatorVault.addStrategy(strategyAddr, allocationPoints);

        IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(strategyAddr);

        assertEq(eulerYieldAggregatorVault.totalAllocationPoints(), allocationPoints + totalAllocationPointsBefore);
        assertEq(strategy.allocated, 0);
        assertEq(strategy.allocationPoints, allocationPoints);
    }
}
