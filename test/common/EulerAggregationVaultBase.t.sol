// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
import {IWithdrawalQueue} from "../../src/core/interface/IWithdrawalQueue.sol";
// contracts
import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {EulerAggregationVault, IEulerAggregationVault} from "../../src/core/EulerAggregationVault.sol";
import {Hooks, HooksModule} from "../../src/core/module/Hooks.sol";
import {Rewards} from "../../src/core/module/Rewards.sol";
import {Fee} from "../../src/core/module/Fee.sol";
import {Rebalance} from "../../src/core/module/Rebalance.sol";
import {EulerAggregationVaultFactory} from "../../src/core/EulerAggregationVaultFactory.sol";
import {WithdrawalQueue} from "../../src/plugin/WithdrawalQueue.sol";
import {Strategy} from "../../src/core/module/Strategy.sol";
// libs
import {ErrorsLib} from "../../src/core/lib/ErrorsLib.sol";
import {ErrorsLib} from "../../src/core/lib/ErrorsLib.sol";
import {AmountCapLib as AggAmountCapLib, AmountCap as AggAmountCap} from "../../src/core/lib/AmountCapLib.sol";

contract EulerAggregationVaultBase is EVaultTestBase {
    using AggAmountCapLib for AggAmountCap;

    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address deployer;
    address user1;
    address user2;
    address manager;

    // core modules
    Rewards rewardsImpl;
    Hooks hooksImpl;
    Fee feeModuleImpl;
    Strategy strategyModuleImpl;
    Rebalance rebalanceModuleImpl;
    // plugins
    WithdrawalQueue withdrawalQueueImpl;

    EulerAggregationVaultFactory eulerAggregationVaultFactory;
    EulerAggregationVault eulerAggregationVault;
    WithdrawalQueue withdrawalQueue;

    function setUp() public virtual override {
        super.setUp();

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");
        manager = makeAddr("Manager");

        vm.startPrank(deployer);
        rewardsImpl = new Rewards();
        hooksImpl = new Hooks();
        feeModuleImpl = new Fee();
        strategyModuleImpl = new Strategy();
        rebalanceModuleImpl = new Rebalance();

        withdrawalQueueImpl = new WithdrawalQueue();

        EulerAggregationVaultFactory.FactoryParams memory factoryParams = EulerAggregationVaultFactory.FactoryParams({
            owner: deployer,
            balanceTracker: address(0),
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            strategyModuleImpl: address(strategyModuleImpl),
            rebalanceModuleImpl: address(rebalanceModuleImpl)
        });
        eulerAggregationVaultFactory = new EulerAggregationVaultFactory(factoryParams);
        // eulerAggregationVaultFactory.whitelistWithdrawalQueueImpl(address(withdrawalQueueImpl));

        eulerAggregationVault = EulerAggregationVault(
            eulerAggregationVaultFactory.deployEulerAggregationVault(
                address(withdrawalQueueImpl),
                address(assetTST),
                "assetTST_Agg",
                "assetTST_Agg",
                CASH_RESERVE_ALLOCATION_POINTS
            )
        );
        withdrawalQueue = WithdrawalQueue(eulerAggregationVault.withdrawalQueue());

        // grant admin roles to deployer
        eulerAggregationVault.grantRole(eulerAggregationVault.GUARDIAN_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_OPERATOR_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer);

        // grant roles to manager
        eulerAggregationVault.grantRole(eulerAggregationVault.GUARDIAN(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_OPERATOR(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER(), manager);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager);

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
            withdrawalQueue.getRoleAdmin(withdrawalQueue.WITHDRAW_QUEUE_MANAGER()),
            withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN()
        );

        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_OPERATOR_ADMIN(), deployer));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer));

        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_OPERATOR(), manager));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.AGGREGATION_VAULT_MANAGER(), manager));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager));

        // assertEq(eulerAggregationVaultFactory.getWithdrawalQueueImplsListLength(), 1);
        // address[] memory withdrawalQueueList = eulerAggregationVaultFactory.getWithdrawalQueueImplsList();
        // assertEq(withdrawalQueueList.length, 1);
        // assertEq(address(withdrawalQueueList[0]), address(withdrawalQueueImpl));

        assertEq(eulerAggregationVaultFactory.getAggregationVaultsListLength(), 1);
        address[] memory aggregationVaultsList = eulerAggregationVaultFactory.getAggregationVaultsListSlice(0, 1);
        assertEq(aggregationVaultsList.length, 1);
        assertEq(address(aggregationVaultsList[0]), address(eulerAggregationVault));
    }

    // function testWhitelistWithdrawalQueueImpl() public {
    //     address newWithdrawalQueueImpl = makeAddr("NEW_WITHDRAWAL_QUEUE_IMPL");

    //     vm.prank(deployer);
    //     eulerAggregationVaultFactory.whitelistWithdrawalQueueImpl(newWithdrawalQueueImpl);

    //     assertEq(eulerAggregationVaultFactory.isWhitelistedWithdrawalQueueImpl(newWithdrawalQueueImpl), true);
    //     address[] memory withdrawalQueueList = eulerAggregationVaultFactory.getWithdrawalQueueImplsList();
    //     assertEq(withdrawalQueueList.length, 2);
    //     assertEq(address(withdrawalQueueList[1]), address(newWithdrawalQueueImpl));

    //     vm.prank(deployer);
    //     vm.expectRevert(EulerAggregationVaultFactory.WithdrawalQueueAlreadyWhitelisted.selector);
    //     eulerAggregationVaultFactory.whitelistWithdrawalQueueImpl(newWithdrawalQueueImpl);
    // }

    // function testDeployEulerAggregationVaultWithRandomWithdrawalQueue() public {
    //     address newWithdrawalQueueImpl = makeAddr("NEW_WITHDRAWAL_QUEUE_IMPL");

    //     vm.expectRevert(EulerAggregationVaultFactory.NotWhitelistedWithdrawalQueueImpl.selector);
    //     eulerAggregationVaultFactory.deployEulerAggregationVault(
    //         newWithdrawalQueueImpl, address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
    //     );

    //     address[] memory aggregationVaultsList =
    //         eulerAggregationVaultFactory.getAggregationVaultsListSlice(0, type(uint256).max);
    //     assertEq(aggregationVaultsList.length, 1);
    //     assertEq(address(aggregationVaultsList[0]), address(eulerAggregationVault));

    //     vm.expectRevert(EulerAggregationVaultFactory.InvalidQuery.selector);
    //     eulerAggregationVaultFactory.getAggregationVaultsListSlice(1, 0);
    // }

    function testDeployEulerAggregationVaultWithInvalidInitialCashAllocationPoints() public {
        vm.expectRevert(ErrorsLib.InitialAllocationPointsZero.selector);
        eulerAggregationVaultFactory.deployEulerAggregationVault(
            address(withdrawalQueueImpl), address(assetTST), "assetTST_Agg", "assetTST_Agg", 0
        );
    }

    function _addStrategy(address from, address strategy, uint256 allocationPoints) internal {
        vm.prank(from);
        eulerAggregationVault.addStrategy(strategy, allocationPoints);
    }

    function _getWithdrawalQueueLength() internal view returns (uint256) {
        uint256 length = withdrawalQueue.withdrawalQueueLength();

        return length;
    }

    function _getWithdrawalQueue() internal view returns (address[] memory) {
        uint256 length = withdrawalQueue.withdrawalQueueLength();

        address[] memory queue = new address[](length);
        for (uint256 i = 0; i < length; ++i) {
            queue[i] = withdrawalQueue.getWithdrawalQueueAtIndex(i);
        }
        return queue;
    }
}
