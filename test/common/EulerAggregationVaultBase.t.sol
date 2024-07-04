// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
import {IWithdrawalQueue} from "../../src/core/interface/IWithdrawalQueue.sol";
// contracts
import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {EulerAggregationVault, IEulerAggregationVault} from "../../src/core/EulerAggregationVault.sol";
import {Rebalancer} from "../../src/plugin/Rebalancer.sol";
import {Hooks, HooksModule} from "../../src/core/module/Hooks.sol";
import {Rewards} from "../../src/core/module/Rewards.sol";
import {Fee} from "../../src/core/module/Fee.sol";
import {EulerAggregationVaultFactory} from "../../src/core/EulerAggregationVaultFactory.sol";
import {WithdrawalQueue} from "../../src/plugin/WithdrawalQueue.sol";
import {AllocationPoints} from "../../src/core/module/AllocationPoints.sol";
// libs
import {ErrorsLib} from "../../src/core/lib/ErrorsLib.sol";

contract EulerAggregationVaultBase is EVaultTestBase {
    uint256 public constant CASH_RESERVE_ALLOCATION_POINTS = 1000e18;

    address deployer;
    address user1;
    address user2;
    address manager;

    // core modules
    Rewards rewardsImpl;
    Hooks hooksImpl;
    Fee feeModuleImpl;
    AllocationPoints allocationPointsModuleImpl;
    // plugins
    Rebalancer rebalancer;
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
        allocationPointsModuleImpl = new AllocationPoints();

        rebalancer = new Rebalancer();
        withdrawalQueueImpl = new WithdrawalQueue();

        EulerAggregationVaultFactory.FactoryParams memory factoryParams = EulerAggregationVaultFactory.FactoryParams({
            balanceTracker: address(0),
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            allocationPointsModuleImpl: address(allocationPointsModuleImpl),
            rebalancer: address(rebalancer),
            withdrawalQueueImpl: address(withdrawalQueueImpl)
        });
        eulerAggregationVaultFactory = new EulerAggregationVaultFactory(factoryParams);

        eulerAggregationVault = EulerAggregationVault(
            eulerAggregationVaultFactory.deployEulerAggregationVault(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );
        withdrawalQueue = WithdrawalQueue(eulerAggregationVault.withdrawalQueue());

        // grant admin roles to deployer
        eulerAggregationVault.grantRole(eulerAggregationVault.ALLOCATIONS_MANAGER_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_ADDER_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_REMOVER_ADMIN(), deployer);
        eulerAggregationVault.grantRole(eulerAggregationVault.AGGREGATION_LAYER_MANAGER_ADMIN(), deployer);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer);

        // grant roles to manager
        eulerAggregationVault.grantRole(eulerAggregationVault.ALLOCATIONS_MANAGER(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_ADDER(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.STRATEGY_REMOVER(), manager);
        eulerAggregationVault.grantRole(eulerAggregationVault.AGGREGATION_LAYER_MANAGER(), manager);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager);

        vm.stopPrank();

        vm.label(address(eulerAggregationVaultFactory), "eulerAggregationVaultFactory");
        vm.label(address(eulerAggregationVault), "eulerAggregationVault");
        vm.label(eulerAggregationVault.MODULE_REWARDS(), "MODULE_REWARDS");
        vm.label(eulerAggregationVault.MODULE_HOOKS(), "MODULE_HOOKS");
        vm.label(eulerAggregationVault.MODULE_FEE(), "MODULE_FEE");
        vm.label(eulerAggregationVault.MODULE_ALLOCATION_POINTS(), "MODULE_ALLOCATION_POINTS");
        vm.label(address(assetTST), "assetTST");
    }

    function testInitialParams() public view {
        EulerAggregationVault.Strategy memory cashReserve = eulerAggregationVault.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.active, true);

        assertEq(
            eulerAggregationVault.getRoleAdmin(eulerAggregationVault.ALLOCATIONS_MANAGER()),
            eulerAggregationVault.ALLOCATIONS_MANAGER_ADMIN()
        );
        assertEq(
            eulerAggregationVault.getRoleAdmin(eulerAggregationVault.STRATEGY_ADDER()),
            eulerAggregationVault.STRATEGY_ADDER_ADMIN()
        );
        assertEq(
            eulerAggregationVault.getRoleAdmin(eulerAggregationVault.STRATEGY_REMOVER()),
            eulerAggregationVault.STRATEGY_REMOVER_ADMIN()
        );
        assertEq(
            eulerAggregationVault.getRoleAdmin(eulerAggregationVault.AGGREGATION_LAYER_MANAGER()),
            eulerAggregationVault.AGGREGATION_LAYER_MANAGER_ADMIN()
        );
        assertEq(
            withdrawalQueue.getRoleAdmin(withdrawalQueue.WITHDRAW_QUEUE_MANAGER()),
            withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN()
        );

        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.ALLOCATIONS_MANAGER_ADMIN(), deployer));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_ADDER_ADMIN(), deployer));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_REMOVER_ADMIN(), deployer));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.AGGREGATION_LAYER_MANAGER_ADMIN(), deployer));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer));

        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.ALLOCATIONS_MANAGER(), manager));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_ADDER(), manager));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.STRATEGY_REMOVER(), manager));
        assertTrue(eulerAggregationVault.hasRole(eulerAggregationVault.AGGREGATION_LAYER_MANAGER(), manager));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager));
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
