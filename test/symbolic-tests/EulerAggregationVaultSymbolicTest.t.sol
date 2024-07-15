// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;


import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {
    EulerAggregationVaultBase,
    EulerAggregationVault,
    IWithdrawalQueue,
    IEVault,
    TestERC20,
    IEulerAggregationVault,
    WithdrawalQueue
} from "../common/EulerAggregationVaultBase.t.sol";

contract MyTokenTest is EulerAggregationVaultBase, SymTest {

    function setUp() public override {
        super.setUp();
        
        uint256 initialCashReservePointsAllocation = svm.createUint256('initialCashReservePointsAllocation');
        vm.assume(1 <= initialCashReservePointsAllocation && initialCashReservePointsAllocation <= type(uint120).max);

        vm.startPrank(deployer);
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
    }

    // AllocationPoints module's functions
    function check_adjustAllocationPoints() public {
        address strategy = svm.createAddress("strategy");
        uint256 newPoints = svm.createUint256("newPoints");

        vm.assume(newPoints <= type(uint120).max);

        vm.prank(manager);
        eulerAggregationVault.adjustAllocationPoints(strategy, newPoints);
    }
}
