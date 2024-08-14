// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
// contracts
import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {EulerAggregationVault, IEulerAggregationVault} from "../../src/EulerAggregationVault.sol";
import {Hooks, HooksModule} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {Rebalance} from "../../src/module/Rebalance.sol";
import {WithdrawalQueue} from "../../src/module/WithdrawalQueue.sol";
import {EulerAggregationVaultFactory} from "../../src/EulerAggregationVaultFactory.sol";
import {Strategy} from "../../src/module/Strategy.sol";
// libs
import {ErrorsLib} from "../../src/lib/ErrorsLib.sol";
import {ErrorsLib} from "../../src/lib/ErrorsLib.sol";
import {AmountCapLib as AggAmountCapLib, AmountCap as AggAmountCap} from "../../src/lib/AmountCapLib.sol";

contract EulerAggregationVaultBase is EVaultTestBase {
    using AggAmountCapLib for AggAmountCap;

    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address deployer;
    address user1;
    address user2;
    address manager;

    // core modules
    Rewards rewardsModule;
    Hooks hooksModule;
    Fee feeModuleModule;
    Strategy strategyModuleModule;
    Rebalance rebalanceModuleModule;
    WithdrawalQueue withdrawalQueueModuleModule;

    EulerAggregationVaultFactory eulerAggregationVaultFactory;
    EulerAggregationVault eulerAggregationVault;

    function setUp() public virtual override {
        super.setUp();

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");
        manager = makeAddr("Manager");

        vm.startPrank(deployer);
        rewardsModule = new Rewards(address(evc));
        hooksModule = new Hooks(address(evc));
        feeModuleModule = new Fee(address(evc));
        strategyModuleModule = new Strategy(address(evc));
        rebalanceModuleModule = new Rebalance(address(evc));
        withdrawalQueueModuleModule = new WithdrawalQueue(address(evc));

        EulerAggregationVaultFactory.FactoryParams memory factoryParams = EulerAggregationVaultFactory.FactoryParams({
            owner: deployer,
            evc: address(evc),
            balanceTracker: address(0),
            rewardsModule: address(rewardsModule),
            hooksModule: address(hooksModule),
            feeModule: address(feeModuleModule),
            strategyModule: address(strategyModuleModule),
            rebalanceModule: address(rebalanceModuleModule),
            withdrawalQueueModule: address(withdrawalQueueModuleModule)
        });
        eulerAggregationVaultFactory = new EulerAggregationVaultFactory(factoryParams);
        eulerAggregationVault = EulerAggregationVault(
            eulerAggregationVaultFactory.deployEulerAggregationVault(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );

        // grant admin roles to deployer
        eulerAggregationVault.grantRole(eulerAggregationVault.GUARDIAN_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_OPERATOR_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.WITHDRAWAL_QUEUE_MANAGER_ADMIN(), deployer);

        // grant roles to manager
        eulerAggregationVault.grantRole(eulerAggregationVault.GUARDIAN(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_OPERATOR(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.WITHDRAWAL_QUEUE_MANAGER(), manager);

        vm.stopPrank();

        vm.label(address(eulerAggregationVaultFactory), "eulerAggregationVaultFactory");
        vm.label(address(eulerAggregationVault), "eulerAggregationVault");
        vm.label(eulerAggregationVault.rewardsModule(), "rewardsModule");
        vm.label(eulerAggregationVault.hooksModule(), "hooksModule");
        vm.label(eulerAggregationVault.feeModule(), "feeModule");
        vm.label(eulerAggregationVault.strategyModule(), "strategyModule");
        vm.label(address(assetTST), "assetTST");
    }

    function testInitialParams() public view {
        EulerAggregationVault.Strategy memory cashReserve = eulerAggregationVault.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.status == IEulerAggregationVault.StrategyStatus.Active, true);

        assertEq(
            eulerAggregationVault.getRoleAdmin(eulerAggregationVault.STRATEGY_OPERATOR()),
            eulerAggregationVault.STRATEGY_OPERATOR_ADMIN()
        );
        assertEq(
            eulerAggregationVault.getRoleAdmin(eulerAggregationVault.AGGREGATION_VAULT_MANAGER()),
            eulerAggregationVault.AGGREGATION_VAULT_MANAGER_ADMIN()
        );
        assertEq(
            eulerAggregationVault.getRoleAdmin(eulerAggregationVault.WITHDRAWAL_QUEUE_MANAGER()),
            eulerAggregationVault.WITHDRAWAL_QUEUE_MANAGER_ADMIN()
        );

        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_OPERATOR_ADMIN(), deployer));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.WITHDRAWAL_QUEUE_MANAGER_ADMIN(), deployer));

        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_OPERATOR(), manager));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER(), manager));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.WITHDRAWAL_QUEUE_MANAGER(), manager));

        assertEq(eulerAggregationVaultFactory.getAggregationVaultsListLength(), 1);
        address[] memory aggregationVaultsList = eulerAggregationVaultFactory.getAggregationVaultsListSlice(0, 1);
        assertEq(aggregationVaultsList.length, 1);
        assertEq(address(aggregationVaultsList[0]), address(eulerAggregationVault));
    }

    function testDeployEulerAggregationVaultWithInvalidInitialCashAllocationPoints() public {
        vm.expectRevert(ErrorsLib.InitialAllocationPointsZero.selector);
        eulerAggregationVaultFactory.deployEulerAggregationVault(address(assetTST), "assetTST_Agg", "assetTST_Agg", 0);
    }

    function _addStrategy(address from, address strategy, uint256 allocationPoints) internal {
        vm.prank(from);
        eulerAggregationVault.addStrategy(strategy, allocationPoints);
    }

    function _getWithdrawalQueue() internal view returns (address[] memory) {
        return eulerAggregationVault.withdrawalQueue();
    }

    function _getWithdrawalQueueLength() internal view returns (uint256) {
        address[] memory withdrawalQueueArray = eulerAggregationVault.withdrawalQueue();
        return withdrawalQueueArray.length;
    }
}
