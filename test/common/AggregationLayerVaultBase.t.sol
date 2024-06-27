// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

// interfaces
import {IHookTarget} from "evk/src/interfaces/IHookTarget.sol";
import {IWithdrawalQueue} from "../../src/interface/IWithdrawalQueue.sol";
// contracts
import "evk/test/unit/evault/EVaultTestBase.t.sol";
import {AggregationLayerVault, IAggregationLayerVault} from "../../src/AggregationLayerVault.sol";
import {Rebalancer} from "../../src/plugin/Rebalancer.sol";
import {Hooks, HooksModule} from "../../src/module/Hooks.sol";
import {Rewards} from "../../src/module/Rewards.sol";
import {Fee} from "../../src/module/Fee.sol";
import {AggregationLayerVaultFactory} from "../../src/AggregationLayerVaultFactory.sol";
import {WithdrawalQueue} from "../../src/plugin/WithdrawalQueue.sol";
import {AllocationPoints} from "../../src/module/AllocationPoints.sol";
// libs
import {ErrorsLib} from "../../src/lib/ErrorsLib.sol";

contract AggregationLayerVaultBase is EVaultTestBase {
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

    AggregationLayerVaultFactory aggregationLayerVaultFactory;
    AggregationLayerVault aggregationLayerVault;
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

        AggregationLayerVaultFactory.FactoryParams memory factoryParams = AggregationLayerVaultFactory.FactoryParams({
            evc: address(evc),
            balanceTracker: address(0),
            rewardsModuleImpl: address(rewardsImpl),
            hooksModuleImpl: address(hooksImpl),
            feeModuleImpl: address(feeModuleImpl),
            allocationPointsModuleImpl: address(allocationPointsModuleImpl),
            rebalancer: address(rebalancer),
            withdrawalQueueImpl: address(withdrawalQueueImpl)
        });
        aggregationLayerVaultFactory = new AggregationLayerVaultFactory(factoryParams);

        aggregationLayerVault = AggregationLayerVault(
            aggregationLayerVaultFactory.deployEulerAggregationLayer(
                address(assetTST), "assetTST_Agg", "assetTST_Agg", CASH_RESERVE_ALLOCATION_POINTS
            )
        );
        withdrawalQueue = WithdrawalQueue(aggregationLayerVault.withdrawalQueue());

        // grant admin roles to deployer
        aggregationLayerVault.grantRole(aggregationLayerVault.ALLOCATIONS_MANAGER_ADMIN(), deployer);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_ADDER_ADMIN(), deployer);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_REMOVER_ADMIN(), deployer);
        aggregationLayerVault.grantRole(aggregationLayerVault.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer);
        aggregationLayerVault.grantRole(aggregationLayerVault.REBALANCER_ADMIN(), deployer);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer);

        // grant roles to manager
        aggregationLayerVault.grantRole(aggregationLayerVault.ALLOCATIONS_MANAGER(), manager);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_ADDER(), manager);
        aggregationLayerVault.grantRole(aggregationLayerVault.STRATEGY_REMOVER(), manager);
        aggregationLayerVault.grantRole(aggregationLayerVault.AGGREGATION_VAULT_MANAGER(), manager);
        withdrawalQueue.grantRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager);

        vm.stopPrank();
    }

    function testInitialParams() public {
        AggregationLayerVault.Strategy memory cashReserve = aggregationLayerVault.getStrategy(address(0));

        assertEq(cashReserve.allocated, 0);
        assertEq(cashReserve.allocationPoints, CASH_RESERVE_ALLOCATION_POINTS);
        assertEq(cashReserve.active, true);

        assertEq(
            aggregationLayerVault.getRoleAdmin(aggregationLayerVault.ALLOCATIONS_MANAGER()),
            aggregationLayerVault.ALLOCATIONS_MANAGER_ADMIN()
        );
        assertEq(
            aggregationLayerVault.getRoleAdmin(aggregationLayerVault.STRATEGY_ADDER()),
            aggregationLayerVault.STRATEGY_ADDER_ADMIN()
        );
        assertEq(
            aggregationLayerVault.getRoleAdmin(aggregationLayerVault.STRATEGY_REMOVER()),
            aggregationLayerVault.STRATEGY_REMOVER_ADMIN()
        );
        assertEq(
            aggregationLayerVault.getRoleAdmin(aggregationLayerVault.AGGREGATION_VAULT_MANAGER()),
            aggregationLayerVault.AGGREGATION_VAULT_MANAGER_ADMIN()
        );
        assertEq(
            withdrawalQueue.getRoleAdmin(withdrawalQueue.WITHDRAW_QUEUE_MANAGER()),
            withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN()
        );

        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.ALLOCATIONS_MANAGER_ADMIN(), deployer));
        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.STRATEGY_ADDER_ADMIN(), deployer));
        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.STRATEGY_REMOVER_ADMIN(), deployer));
        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.AGGREGATION_VAULT_MANAGER_ADMIN(), deployer));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER_ADMIN(), deployer));

        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.ALLOCATIONS_MANAGER(), manager));
        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.STRATEGY_ADDER(), manager));
        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.STRATEGY_REMOVER(), manager));
        assertTrue(aggregationLayerVault.hasRole(aggregationLayerVault.AGGREGATION_VAULT_MANAGER(), manager));
        assertTrue(withdrawalQueue.hasRole(withdrawalQueue.WITHDRAW_QUEUE_MANAGER(), manager));
    }

    function _addStrategy(address from, address strategy, uint256 allocationPoints) internal {
        vm.prank(from);
        aggregationLayerVault.addStrategy(strategy, allocationPoints);
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
