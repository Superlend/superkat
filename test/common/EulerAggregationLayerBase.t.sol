// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
import {IWithdrawalQueue} from "../../src/interface/IWithdrawalQueue.sol";
// contracts
import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {EulerAggregationLayer, IEulerAggregationLayer} from "../../src/EulerAggregationLayer.sol";
import {Rebalancer} from "../../src/plugin/Rebalancer.sol";
import {Hooks, HooksModule} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {EulerAggregationLayerFactory} from "../../src/EulerAggregationLayerFactory.sol";
import {WithdrawalQueue} from "../../src/plugin/WithdrawalQueue.sol";
import {AllocationPoints} from "../../src/module/AllocationPoints.sol";
// libs
import {ErrorsLib} from "../../src/lib/ErrorsLib.sol";

contract EulerAggregationLayerBase is EVaultTestBase {
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

    EulerAggregationLayerFactory eulerAggregationLayerFactory;
    EulerAggregationLayer eulerAggregationLayer;
    WithdrawalQueue withdrawalQueue;

    function setUp() public virtual override {
        super.setUp();

        deployer = makeAddr("Deployer");
        user1 = makeAddr("User_1");
        user2 = makeAddr("User_2");

        vm.startPrank(deployer);
        rewardsImpl = new Rewards();
        hooksImpl = new Hooks();
        feeModuleImpl = new Fee();
        allocationPointsModuleImpl = new AllocationPoints();

        rebalancer = new Rebalancer();
        withdrawalQueueImpl = new WithdrawalQueue();

        EulerAggregationLayerFactory.FactoryParams memory factoryParams = EulerAggregationLayerFactory.FactoryParams({
            evc: address(evc),
            balanceTracker: address(0),
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            allocationPointsModuleImpl: address(allocationPointsModuleImpl),
            rebalancer: address(rebalancer),
            withdrawalQueueImpl: address(withdrawalQueueImpl)
        });
        eulerAggregationLayerFactory = new EulerAggregationLayerFactory(factoryParams);

        eulerAggregationLayer = EulerAggregationLayer(
            eulerAggregationLayerFactory.deployEulerAggregationLayer(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );
        withdrawalQueue = WithdrawalQueue(eulerAggregationLayer.withdrawalQueue());

        // grant admin roles to deployer
        eulerAggregationLayer.grantRole(eulerAggregationLayer.ALLOCATIONS_MANAGER_ADMIN(), deployer);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_ADDER_ADMIN(), deployer);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_REMOVER_ADMIN(), deployer);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.REBALANCER_ADMIN(), deployer);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer);

        // grant roles to manager
        eulerAggregationLayer.grantRole(eulerAggregationLayer.ALLOCATIONS_MANAGER(), manager);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_ADDER(), manager);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.STRATEGY_REMOVER(), manager);
        eulerAggregationLayer.grantRole(eulerAggregationLayer.AGGREGATION_VAULT_MANAGER(), manager);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager);

        vm.stopPrank();
    }

    function testInitialParams() public {
        EulerAggregationLayer.Strategy memory cashReserve = eulerAggregationLayer.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.active, true);

        assertEq(
            eulerAggregationLayer.getRoleAdmin(eulerAggregationLayer.ALLOCATIONS_MANAGER()),
            eulerAggregationLayer.ALLOCATIONS_MANAGER_ADMIN()
        );
        assertEq(
            eulerAggregationLayer.getRoleAdmin(eulerAggregationLayer.STRATEGY_ADDER()),
            eulerAggregationLayer.STRATEGY_ADDER_ADMIN()
        );
        assertEq(
            eulerAggregationLayer.getRoleAdmin(eulerAggregationLayer.STRATEGY_REMOVER()),
            eulerAggregationLayer.STRATEGY_REMOVER_ADMIN()
        );
        assertEq(
            eulerAggregationLayer.getRoleAdmin(eulerAggregationLayer.AGGREGATION_VAULT_MANAGER()),
            eulerAggregationLayer.AGGREGATION_VAULT_MANAGER_ADMIN()
        );
        assertEq(
            withdrawalQueue.getRoleAdmin(withdrawalQueue.WITHDRAW_QUEUE_MANAGER()),
            withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN()
        );

        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.ALLOCATIONS_MANAGER_ADMIN(), deployer));
        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.STRATEGY_ADDER_ADMIN(), deployer));
        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.STRATEGY_REMOVER_ADMIN(), deployer));
        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer));

        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.ALLOCATIONS_MANAGER(), manager));
        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.STRATEGY_ADDER(), manager));
        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.STRATEGY_REMOVER(), manager));
        assertTrue(eulerAggregationLayer.hasRole(eulerAggregationLayer.AGGREGATION_VAULT_MANAGER(), manager));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager));
    }

    function _addStrategy(address from, address strategy, uint256 allocationPoints) internal {
        vm.prank(from);
        eulerAggregationLayer.addStrategy(strategy, allocationPoints);
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
