// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {
    YieldAggregatorBase,
    YieldAggregator,
    IEVault,
    TestERC20,
    IYieldAggregator,
    ConstantsLib
} from "../common/YieldAggregatorBase.t.sol";

contract MyTokenTest is YieldAggregatorBase, SymTest {
    function setUp() public override {
        super.setUp();

        uint256 initialCashReservePointsAllocation = svm.createUint256("initialCashReservePointsAllocation");
        vm.assume(1 <= initialCashReservePointsAllocation && initialCashReservePointsAllocation <= type(uint120).max);

        vm.startPrank(deployer);
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

    // AllocationPoints module's functions
    function check_adjustAllocationPoints() public {
        address strategy = svm.createAddress("strategy");
        uint256 newPoints = svm.createUint256("newPoints");

        vm.assume(newPoints <= type(uint120).max);

        vm.prank(manager);
        eulerYieldAggregatorVault.adjustAllocationPoints(strategy, newPoints);
    }
}
