// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {
    EulerAggregationLayerBase,
    EulerAggregationLayer,
    IWithdrawalQueue,
    console2
} from "../common/EulerAggregationLayerBase.t.sol";
import {Actor} from "./util/Actor.sol";
import {Strategy} from "./util/Strategy.sol";
import {EulerAggregationLayerHandler} from "./handler/EulerAggregationLayerHandler.sol";
import {RebalancerHandler} from "./handler/RebalancerHandler.sol";

contract EulerAggregationLayerInvariants is EulerAggregationLayerBase {
    Actor internal actorUtil;
    Strategy internal strategyUtil;

    EulerAggregationLayerHandler internal eulerAggregationLayerHandler;
    RebalancerHandler internal rebalancerHandler;

    function setUp() public override {
        super.setUp();

        actorUtil = new Actor();
        actorUtil.addActor(manager);
        actorUtil.addActor(deployer);
        actorUtil.addActor(user1);
        actorUtil.addActor(user2);

        strategyUtil = new Strategy();
        strategyUtil.includeStrategy(address(eTST));

        eulerAggregationLayerHandler = new EulerAggregationLayerHandler(eulerAggregationLayer, actorUtil, strategyUtil);
        rebalancerHandler =
            new RebalancerHandler(eulerAggregationLayer, rebalancer, actorUtil, strategyUtil, withdrawalQueue);

        targetContract(address(eulerAggregationLayerHandler));
        targetContract(address(rebalancerHandler));
    }

    function invariant_totalAllocationPoints() public view {
        address withdrawalQueueAddr = eulerAggregationLayer.withdrawalQueue();

        (address[] memory withdrawalQueueArray, uint256 withdrawalQueueLength) =
            IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 expectedTotalAllocationpoints;
        expectedTotalAllocationpoints += (eulerAggregationLayer.getStrategy(address(0))).allocationPoints;
        for (uint256 i; i < withdrawalQueueLength; i++) {
            expectedTotalAllocationpoints +=
                (eulerAggregationLayer.getStrategy(withdrawalQueueArray[i])).allocationPoints;
        }

        assertEq(eulerAggregationLayer.totalAllocationPoints(), expectedTotalAllocationpoints);
    }

    function invariant_withdrawalQueue() public view {
        address withdrawalQueueAddr = eulerAggregationLayer.withdrawalQueue();

        (, uint256 withdrawalQueueLength) = IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 cashReserveAllocationPoints = (eulerAggregationLayer.getStrategy(address(0))).allocationPoints;

        if (eulerAggregationLayer.totalAllocationPoints() - cashReserveAllocationPoints == 0) {
            assertEq(withdrawalQueueLength, 0);
        } else {
            assertGt(withdrawalQueueLength, 0);
        }
    }

    function invariant_totalAllocated() public view {
        address withdrawalQueueAddr = eulerAggregationLayer.withdrawalQueue();

        (address[] memory withdrawalQueueArray, uint256 withdrawalQueueLength) =
            IWithdrawalQueue(withdrawalQueueAddr).getWithdrawalQueueArray();

        uint256 aggregatedAllocatedAmount;
        for (uint256 i; i < withdrawalQueueLength; i++) {
            aggregatedAllocatedAmount += (eulerAggregationLayer.getStrategy(withdrawalQueueArray[i])).allocated;
        }

        assertEq(eulerAggregationLayer.totalAllocated(), aggregatedAllocatedAmount);
    }
}
