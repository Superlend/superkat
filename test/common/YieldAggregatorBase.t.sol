// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
// contracts
import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {YieldAggregator, IYieldAggregator} from "../../src/YieldAggregator.sol";
import {YieldAggregatorVault} from "../../src/module/YieldAggregatorVault.sol";
import {Hooks, HooksModule} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {Rebalance} from "../../src/module/Rebalance.sol";
import {WithdrawalQueue} from "../../src/module/WithdrawalQueue.sol";
import {YieldAggregatorFactory} from "../../src/YieldAggregatorFactory.sol";
import {Strategy} from "../../src/module/Strategy.sol";
// libs
import {ErrorsLib} from "../../src/lib/ErrorsLib.sol";
import {ErrorsLib} from "../../src/lib/ErrorsLib.sol";
import {AmountCapLib as AggAmountCapLib, AmountCap as AggAmountCap} from "../../src/lib/AmountCapLib.sol";
import {ConstantsLib} from "../../src/lib/ConstantsLib.sol";

contract YieldAggregatorBase is EVaultTestBase {
    using AggAmountCapLib for AggAmountCap;

    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address deployer;
    address user1;
    address user2;
    address manager;

    // core modules
    YieldAggregatorVault yieldAggregatorVaultModule;
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModuleModule;
    Strategy strategyModuleModule;
    Rebalance rebalanceModuleModule;
    WithdrawalQueue withdrawalQueueModuleModule;

    YieldAggregatorFactory eulerYieldAggregatorVaultFactory;
    YieldAggregator eulerYieldAggregatorVault;

    function setUp() public virtual override {
        super.setUp();

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
    }

    function testInitialParams() public view {
        IYieldAggregator.Strategy memory cashReserve = eulerYieldAggregatorVault.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.status == IYieldAggregator.StrategyStatus.Active, true);

        assertEq(
            eulerYieldAggregatorVault.getRoleAdmin(ConstantsLib.STRATEGY_OPERATOR), ConstantsLib.STRATEGY_OPERATOR_ADMIN
        );
        assertEq(
            eulerYieldAggregatorVault.getRoleAdmin(ConstantsLib.YIELD_AGGREGATOR_MANAGER),
            ConstantsLib.YIELD_AGGREGATOR_MANAGER_ADMIN
        );
        assertEq(
            eulerYieldAggregatorVault.getRoleAdmin(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER),
            ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN
        );

        assertTrue(eulerYieldAggregatorVault.hasRole(ConstantsLib.STRATEGY_OPERATOR_ADMIN, deployer));
        assertTrue(eulerYieldAggregatorVault.hasRole(ConstantsLib.YIELD_AGGREGATOR_MANAGER_ADMIN, deployer));
        assertTrue(eulerYieldAggregatorVault.hasRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER_ADMIN, deployer));

        assertTrue(eulerYieldAggregatorVault.hasRole(ConstantsLib.STRATEGY_OPERATOR, manager));
        assertTrue(eulerYieldAggregatorVault.hasRole(ConstantsLib.YIELD_AGGREGATOR_MANAGER, manager));
        assertTrue(eulerYieldAggregatorVault.hasRole(ConstantsLib.WITHDRAWAL_QUEUE_MANAGER, manager));

        assertEq(eulerYieldAggregatorVaultFactory.getYieldAggregatorVaultsListLength(), 1);
        address[] memory yieldAggregatorVaultsList =
            eulerYieldAggregatorVaultFactory.getYieldAggregatorVaultsListSlice(0, 1);
        assertEq(yieldAggregatorVaultsList.length, 1);
        assertEq(address(yieldAggregatorVaultsList[0]), address(eulerYieldAggregatorVault));
        assertEq(eulerYieldAggregatorVault.decimals(), assetTST.decimals());
    }

    function testDeployYieldAggregatorWithInvalidInitialCashAllocationPoints() public {
        vm.expectRevert(ErrorsLib.InitialAllocationPointsZero.selector);
        eulerYieldAggregatorVaultFactory.deployYieldAggregator(address(assetTST), "assetTST_Agg", "assetTST_Agg", 0);
    }

    function _addStrategy(address from, address strategy, uint256 allocationPoints) internal {
        vm.prank(from);
        eulerYieldAggregatorVault.addStrategy(strategy, allocationPoints);
    }

    function _getWithdrawalQueue() internal view returns (address[] memory) {
        return eulerYieldAggregatorVault.withdrawalQueue();
    }

    function _getWithdrawalQueueLength() internal view returns (uint256) {
        address[] memory withdrawalQueueArray = eulerYieldAggregatorVault.withdrawalQueue();
        return withdrawalQueueArray.length;
    }
}
