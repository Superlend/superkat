// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import "../common/EulerEarnBase.t.sol";

contract EulerEarnSymbolicTest is EulerEarnBase, SymTest {
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
        integrationsParams = Shared.IntegrationsParams({
            evc: address(evc),
            balanceTracker: address(0),
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

        uint256 initialCashReservePointsAllocation = svm.createUint256("initialCashReservePointsAllocation");
        vm.assume(initialCashReservePointsAllocation > 0 && initialCashReservePointsAllocation <= type(uint120).max);

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

        // grant roles to manager
        eulerEulerEarnVault.grantRole(ConstantsLib.GUARDIAN, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.STRATEGY_OPERATOR, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.EULER_EARN_MANAGER, manager);
        eulerEulerEarnVault.grantRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER, manager);
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

            uint256 totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();

            vm.prank(manager);
            eulerEulerEarnVault.addStrategy(strategyAddr, allocationPoints);

            IEulerEarn.Strategy memory strategy = eulerEulerEarnVault.getStrategy(strategyAddr);

            assert(eulerEulerEarnVault.totalAllocationPoints() == allocationPoints + totalAllocationPointsBefore);
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
        eulerEulerEarnVault.addStrategy(strategyAddr, allocationPoints);

        // set cap
        uint256 cap = svm.createUint256("cap");
        vm.assume(cap <= type(uint16).max);

        vm.prank(manager);
        eulerEulerEarnVault.setStrategyCap(strategyAddr, uint16(cap));
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
        eulerEulerEarnVault.addStrategy(strategyAddr, allocationPoints);

        // adjust allocation points
        bool isCashReserveStrategy = svm.createBool("isCashReserveStrategy");
        address strategyAddrToAdjust = (isCashReserveStrategy) ? address(0) : strategyAddr;

        uint256 newAllocationPoints = svm.createUint256("newAllocationPoints");
        if (isCashReserveStrategy) {
            vm.assume(newAllocationPoints > 0 && newAllocationPoints <= type(uint120).max);
        } else {
            vm.assume(newAllocationPoints <= type(uint120).max);
        }

        IEulerEarn.Strategy memory strategyBefore = eulerEulerEarnVault.getStrategy(strategyAddrToAdjust);
        uint256 totalAllocationPointsBefore = eulerEulerEarnVault.totalAllocationPoints();

        vm.prank(manager);
        eulerEulerEarnVault.adjustAllocationPoints(strategyAddrToAdjust, newAllocationPoints);

        IEulerEarn.Strategy memory strategyAfter = eulerEulerEarnVault.getStrategy(strategyAddrToAdjust);

        assert(
            eulerEulerEarnVault.totalAllocationPoints()
                == totalAllocationPointsBefore + newAllocationPoints - strategyBefore.allocationPoints
        );
        assert(strategyAfter.allocationPoints == newAllocationPoints);
    }

    // EulerEarnVault module's functions
    function check_deposit() public {
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        assetTST.mint(user1, amountToDeposit);

        uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        assert(userAssetBalanceBefore >= amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
        uint256 mintedShares = eulerEulerEarnVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        assert(eulerEulerEarnVault.balanceOf(user1) == mintedShares);
        assert(eulerEulerEarnVault.totalSupply() == totalSupplyBefore + mintedShares);
        assert(eulerEulerEarnVault.totalAssetsDeposited() == totalAssetsDepositedBefore + amountToDeposit);
        assert(assetTST.balanceOf(user1) == userAssetBalanceBefore - amountToDeposit);
    }

    function check_mint() public {
        uint256 amountToMint = svm.createUint256("amountToMint");

        uint256 amountToDeposit = eulerEulerEarnVault.previewMint(amountToMint);
        assetTST.mint(user1, amountToDeposit);

        uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        assert(userAssetBalanceBefore >= amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
        uint256 mintedShares = eulerEulerEarnVault.mint(amountToMint, user1);
        vm.stopPrank();

        assert(eulerEulerEarnVault.balanceOf(user1) == mintedShares);
        assert(eulerEulerEarnVault.totalSupply() == totalSupplyBefore + mintedShares);
        assert(eulerEulerEarnVault.totalAssetsDeposited() == totalAssetsDepositedBefore + amountToDeposit);
        assert(assetTST.balanceOf(user1) == userAssetBalanceBefore - amountToDeposit);
    }

    function check_withdraw() public {
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        assetTST.mint(user1, amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
        uint256 mintedShares = eulerEulerEarnVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        assert(eulerEulerEarnVault.balanceOf(user1) == mintedShares);

        uint256 amountToWithdraw = svm.createUint256("amountToDeposit");
        vm.assume(amountToWithdraw <= amountToDeposit);

        uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        vm.prank(user1);
        uint256 burnedShares = eulerEulerEarnVault.withdraw(amountToWithdraw, user1, user1);

        assert(eulerEulerEarnVault.balanceOf(user1) == mintedShares - burnedShares);
        assert(eulerEulerEarnVault.totalSupply() == totalSupplyBefore - burnedShares);
        assert(eulerEulerEarnVault.totalAssetsDeposited() == totalAssetsDepositedBefore - amountToWithdraw);
        assert(assetTST.balanceOf(user1) == userAssetBalanceBefore + amountToWithdraw);
    }

    function check_redeem() public {
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        assetTST.mint(user1, amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
        uint256 mintedShares = eulerEulerEarnVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        assert(eulerEulerEarnVault.balanceOf(user1) == mintedShares);

        uint256 sharesToRedeem = svm.createUint256("sharesToRedeem");
        vm.assume(sharesToRedeem <= mintedShares);

        uint256 totalSupplyBefore = eulerEulerEarnVault.totalSupply();
        uint256 totalAssetsDepositedBefore = eulerEulerEarnVault.totalAssetsDeposited();
        uint256 userAssetBalanceBefore = assetTST.balanceOf(user1);

        vm.prank(user1);
        uint256 withdrawnAssets = eulerEulerEarnVault.redeem(sharesToRedeem, user1, user1);

        assert(eulerEulerEarnVault.balanceOf(user1) == mintedShares - sharesToRedeem);
        assert(eulerEulerEarnVault.totalSupply() == totalSupplyBefore - sharesToRedeem);
        assert(eulerEulerEarnVault.totalAssetsDeposited() == totalAssetsDepositedBefore - withdrawnAssets);
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
            eulerEulerEarnVault.addStrategy(strategyAddr, allocationPoints);
        }

        // deposit
        uint256 amountToDeposit = svm.createUint256("amountToDeposit");
        vm.assume(amountToDeposit > 0);
        assetTST.mint(user1, amountToDeposit);

        vm.startPrank(user1);
        assetTST.approve(address(eulerEulerEarnVault), amountToDeposit);
        eulerEulerEarnVault.deposit(amountToDeposit, user1);
        vm.stopPrank();

        // rebalance
        address[] memory strategies = eulerEulerEarnVault.withdrawalQueue();
        eulerEulerEarnVault.rebalance(strategies);
    }
}
