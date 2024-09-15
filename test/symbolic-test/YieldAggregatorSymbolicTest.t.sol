// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import "../common/YieldAggregatorBase.t.sol";

contract YieldAggregatorSymbolicTest is YieldAggregatorBase, SymTest {
    function setUp() public override {
        admin = address(0x1);
        feeReceiver = address(0x2);
        protocolFeeReceiver = address(0x3);
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

        deployer = address(0x4);
        user1 = address(0x5);
        user2 = address(0x6);
        manager = address(0x7);

        vm.startPrank(deployer);
        integrationsParams =
            Shared.IntegrationsParams({evc: address(evc), balanceTracker: address(0), isHarvestCoolDownCheckOn: true});

        yieldAggregatorVaultModule = new YieldAggregatorVault(integrationsParams);
        rewardsModule = new Rewards(integrationsParams);
        hooksModule = new Hooks(integrationsParams);
        feeModule = new Fee(integrationsParams);
        strategyModule = new Strategy(integrationsParams);
        withdrawalQueueModule = new WithdrawalQueue(integrationsParams);

        deploymentParams = IYieldAggregator.DeploymentParams({
            yieldAggregatorVaultModule: address(yieldAggregatorVaultModule),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModule),
            strategyModule: address(strategyModule),
            withdrawalQueueModule: address(withdrawalQueueModule)
        });
        yieldAggregatorImpl = address(new YieldAggregator(integrationsParams, deploymentParams));

        eulerYieldAggregatorVaultFactory = new YieldAggregatorFactory(yieldAggregatorImpl);

        uint256 initialCashReservePointsAllocation = svm.createUint256("initialCashReservePointsAllocation");
        vm.assume(initialCashReservePointsAllocation > 0 && initialCashReservePointsAllocation <= type(uint120).max);

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
        uint256 numOfStrategies = svm.createUint256("numOfStrategies");
        vm.assume(numOfStrategies <= ConstantsLib.MAX_STRATEGIES);

        // add strategies
        for (uint256 i; i < numOfStrategies; i++) {
            address strategyAddr = address(
                IEVault(
                    factory.createProxy(
                        address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                    )
                )
            );

            uint256 allocationPoints = svm.createUint256("allocationPoints");
            vm.assume(allocationPoints > 0 && allocationPoints <= type(uint120).max);

            uint256 totalAllocationPointsBefore = eulerYieldAggregatorVault.totalAllocationPoints();

            vm.prank(manager);
            eulerYieldAggregatorVault.addStrategy(strategyAddr, allocationPoints);

            IYieldAggregator.Strategy memory strategy = eulerYieldAggregatorVault.getStrategy(strategyAddr);

            assert(eulerYieldAggregatorVault.totalAllocationPoints() == allocationPoints + totalAllocationPointsBefore);
            assert(strategy.allocated == 0);
            assert(strategy.allocationPoints == allocationPoints);
        }
    }

    function check_setStrategyCap() public {
        // add the strategy first
        address strategyAddr = address(
            IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            )
        );
        uint256 allocationPoints = svm.createUint256("allocationPoints");
        vm.assume(allocationPoints > 0 && allocationPoints <= type(uint120).max);
        vm.prank(manager);
        eulerYieldAggregatorVault.addStrategy(strategyAddr, allocationPoints);

        // set cap
        uint256 cap = svm.createUint256("cap");
        vm.assume(cap <= type(uint16).max);

        vm.prank(manager);
        eulerYieldAggregatorVault.setStrategyCap(strategyAddr, uint16(cap));
    }

    function check_adjustAllocationPoints() public {
        // add a strategy
        address strategyAddr = address(
            IEVault(
                factory.createProxy(
                    address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                )
            )
        );
        uint256 allocationPoints = svm.createUint256("allocationPoints");
        vm.assume(allocationPoints > 0 && allocationPoints <= type(uint120).max);

        vm.prank(manager);
        eulerYieldAggregatorVault.addStrategy(strategyAddr, allocationPoints);

        // adjust allocation points
        bool isCashReserveStrategy = svm.createBool("isCashReserveStrategy");
        address strategyAddrToAdjust = (isCashReserveStrategy) ? address(0) : strategyAddr;

        uint256 newAllocationPoints = svm.createUint256("newAllocationPoints");
        if (isCashReserveStrategy) {
            vm.assume(newAllocationPoints > 0 && newAllocationPoints <= type(uint120).max);
        } else {
            vm.assume(newAllocationPoints <= type(uint120).max);
        }

        IYieldAggregator.Strategy memory strategyBefore = eulerYieldAggregatorVault.getStrategy(strategyAddrToAdjust);
        uint256 totalAllocationPointsBefore = eulerYieldAggregatorVault.totalAllocationPoints();

        vm.prank(manager);
        eulerYieldAggregatorVault.adjustAllocationPoints(strategyAddrToAdjust, newAllocationPoints);

        IYieldAggregator.Strategy memory strategyAfter = eulerYieldAggregatorVault.getStrategy(strategyAddrToAdjust);

        assert(
            eulerYieldAggregatorVault.totalAllocationPoints()
                == totalAllocationPointsBefore + newAllocationPoints - strategyBefore.allocationPoints
        );
        assert(strategyAfter.allocationPoints == newAllocationPoints);
    }

    // YieldAggregatorVault module's functions
    function check_deposit() public {
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        assetTST.mint(user1, amountToDeposit);

        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        assert(userAssetBalanceBefore >= amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
        uint256 mintedShares = eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        assert(eulerYieldAggregatorVault.balanceOf(user1) == mintedShares);
        assert(eulerYieldAggregatorVault.totalSupply() == totalSupplyBefore + mintedShares);
        assert(eulerYieldAggregatorVault.totalAssetsDeposited() == totalAssetsDepositedBefore + amountToDeposit);
        assert(assetTST.balanceOf(user1) == userAssetBalanceBefore - amountToDeposit);
    }

    function check_mint() public {
        uint256 amountToMint = svm.createUint256("amountToMint");

        uint256 amountToDeposit = eulerYieldAggregatorVault.previewMint(amountToMint);
        assetTST.mint(user1, amountToDeposit);

        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        assert(userAssetBalanceBefore >= amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
        uint256 mintedShares = eulerYieldAggregatorVault.mint(amountToMint, user1);
        vm.stopPrank();

        assert(eulerYieldAggregatorVault.balanceOf(user1) == mintedShares);
        assert(eulerYieldAggregatorVault.totalSupply() == totalSupplyBefore + mintedShares);
        assert(eulerYieldAggregatorVault.totalAssetsDeposited() == totalAssetsDepositedBefore + amountToDeposit);
        assert(assetTST.balanceOf(user1) == userAssetBalanceBefore - amountToDeposit);
    }

    function check_withdraw() public {
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        assetTST.mint(user1, amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
        uint256 mintedShares = eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        assert(eulerYieldAggregatorVault.balanceOf(user1) == mintedShares);

        uint256 amountToWithdraw = svm.createUint256("amountToDeposit");
        vm.assume(amountToWithdraw <= amountToDeposit);

        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        vm.prank(user1);
        uint256 burnedShares = eulerYieldAggregatorVault.withdraw(amountToWithdraw, user1, user1);

        assert(eulerYieldAggregatorVault.balanceOf(user1) == mintedShares - burnedShares);
        assert(eulerYieldAggregatorVault.totalSupply() == totalSupplyBefore - burnedShares);
        assert(eulerYieldAggregatorVault.totalAssetsDeposited() == totalAssetsDepositedBefore - amountToWithdraw);
        assert(assetTST.balanceOf(user1) == userAssetBalanceBefore + amountToWithdraw);
    }

    function check_redeem() public {
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        assetTST.mint(user1, amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
        uint256 mintedShares = eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        assert(eulerYieldAggregatorVault.balanceOf(user1) == mintedShares);

        uint256 sharesToRedeem = svm.createUint256("sharesToRedeem");
        vm.assume(sharesToRedeem <= mintedShares);

        uint256 totalSupplyBefore = eulerYieldAggregatorVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerYieldAggregatorVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        vm.prank(user1);
        uint256 withdrawnAssets = eulerYieldAggregatorVault.redeem(sharesToRedeem, user1, user1);

        assert(eulerYieldAggregatorVault.balanceOf(user1) == mintedShares - sharesToRedeem);
        assert(eulerYieldAggregatorVault.totalSupply() == totalSupplyBefore - sharesToRedeem);
        assert(eulerYieldAggregatorVault.totalAssetsDeposited() == totalAssetsDepositedBefore - withdrawnAssets);
        assert(assetTST.balanceOf(user1) == userAssetBalanceBefore + withdrawnAssets);
    }

    // Rebalance module's functions
    function check_rebalance() public {
        uint256 numOfStrategies = svm.createUint256("numOfStrategies");
        vm.assume(numOfStrategies <= ConstantsLib.MAX_STRATEGIES);

        // add strategies
        for (uint256 i; i < numOfStrategies; i++) {
            address strategyAddr = address(
                IEVault(
                    factory.createProxy(
                        address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount)
                    )
                )
            );

            uint256 allocationPoints = svm.createUint256("allocationPoints");
            vm.assume(allocationPoints > 0 && allocationPoints <= type(uint120).max);
            vm.prank(manager);
            eulerYieldAggregatorVault.addStrategy(strategyAddr, allocationPoints);
        }

        // deposit
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        vm.assume(amountToDeposit > 0);
        assetTST.mint(user1, amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerYieldAggregatorVault), amountToDeposit);
        eulerYieldAggregatorVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        // rebalance
        address[] memory strategies = eulerYieldAggregatorVault.withdrawalQueue();
        eulerYieldAggregatorVault.rebalance(strategies);
    }
}
